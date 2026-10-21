import Foundation
import Network

/// 基于 Network.framework 的轻量 HTTP/1.1 服务器。
///
/// 每个请求使用独立 TCP 连接，响应后立即关闭（`Connection: close`），
/// 从而避免 keep-alive 状态机带来的复杂度。
final class HTTPServer {
    private let router: Router
    private let queue = DispatchQueue(label: "com.local.wifidrop.server", attributes: .concurrent)
    private let lock = NSLock()
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private var listener: NWListener?

    /// 监听状态回调（是否成功、实际端口）。
    var onStateChange: ((Bool, UInt16?) -> Void)?

    init(router: Router) {
        self.router = router
    }

    /// 从首选端口开始监听，端口被占用时自动递增重试。
    func start(preferredPort: UInt16, attempts: Int = 10) {
        tryListen(port: preferredPort, attemptsLeft: attempts)
    }

    func stop() {
        listener?.cancel()
        listener = nil

        lock.lock()
        let all = Array(connections.values)
        connections.removeAll()
        lock.unlock()

        all.forEach { $0.cancel() }
    }

    private func tryListen(port: UInt16, attemptsLeft: Int) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: endpointPort)
            self.listener = listener
            // 广播 Bonjour 服务：触发 iOS 的「本地网络」权限请求，也便于同网段发现设备。
            listener.service = NWListener.Service(name: "WiFiDrop", type: "_wifidrop._tcp")

            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                switch state {
                case .ready:
                    let actualPort = listener.port?.rawValue ?? port
                    DispatchQueue.main.async { self.onStateChange?(true, actualPort) }
                case .failed:
                    listener.cancel()
                    if let current = self.listener, current === listener {
                        self.listener = nil
                    }
                    if attemptsLeft > 0, port < UInt16.max {
                        self.tryListen(port: port + 1, attemptsLeft: attemptsLeft - 1)
                    } else {
                        DispatchQueue.main.async { self.onStateChange?(false, nil) }
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                let handler = HTTPConnection(connection: connection, router: self.router, queue: self.queue)
                let key = ObjectIdentifier(handler)

                self.lock.lock()
                self.connections[key] = handler
                self.lock.unlock()

                handler.onClose = { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    self.connections.removeValue(forKey: key)
                    self.lock.unlock()
                }
                handler.start()
            }

            listener.start(queue: queue)
        } catch {
            if attemptsLeft > 0, port < UInt16.max {
                tryListen(port: port + 1, attemptsLeft: attemptsLeft - 1)
            } else {
                DispatchQueue.main.async { self.onStateChange?(false, nil) }
            }
        }
    }
}

/// 处理单个 TCP 连接上的一个 HTTP 请求。
final class HTTPConnection {
    private struct UploadState {
        let handle: FileHandle
        let tempURL: URL
        let destination: URL
        var remaining: Int
    }

    private static let tempDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wifidrop-uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private let connection: NWConnection
    private let router: Router
    private let queue: DispatchQueue

    private var buffer = Data()
    private var head: HTTPRequestHead?
    private var upload: UploadState?
    private var isClosed = false
    private var isSending = false

    var onClose: (() -> Void)?

    init(connection: NWConnection, router: Router, queue: DispatchQueue) {
        self.connection = connection
        self.router = router
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive()
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        close()
    }

    // MARK: - 接收

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }

            if let data, !data.isEmpty {
                self.consume(data)
            }
            guard !self.isClosed else { return }

            if error != nil {
                self.close()
                return
            }
            if isComplete {
                // 客户端半关闭时仍要把响应发送完，由发送完成回调负责关闭。
                if !self.isSending {
                    self.close()
                }
                return
            }
            self.receive()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        process()
    }

    private func process() {
        while !isClosed {
            if upload != nil {
                writeUploadBody()
                return
            }

            guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 128 * 1024 {
                    send(.error(431, "请求头过大"))
                }
                return
            }

            let headData = Data(buffer[buffer.startIndex..<separator.lowerBound])
            buffer = Data(buffer[separator.upperBound...])

            do {
                head = try HTTPParser.parseHead(headData)
            } catch {
                send(.error(400, "请求格式错误"))
                return
            }
            guard let parsed = head else { return }

            switch router.route(parsed) {
            case .respond(let response):
                var finalResponse = response
                if parsed.isHeadRequest {
                    finalResponse.declaredLength = finalResponse.body.count
                    finalResponse.sendBody = false
                    finalResponse.body = Data()
                }
                send(finalResponse)
                return

            case .download(let plan):
                sendDownload(plan, headOnly: parsed.isHeadRequest)
                return

            case .upload(let plan):
                beginUpload(plan)
                if upload == nil { return }
            }
        }
    }

    // MARK: - 上传

    private func beginUpload(_ plan: UploadPlan) {
        guard let head = head else { return }

        let tempURL = HTTPConnection.tempDirectory.appendingPathComponent(UUID().uuidString + ".part")
        _ = FileManager.default.createFile(atPath: tempURL.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: tempURL) else {
            send(.error(500, "无法创建临时文件"))
            return
        }

        let destination = FileStore.uniqueDestination(in: plan.destinationDirectory, name: plan.fileName)
        upload = UploadState(handle: handle,
                             tempURL: tempURL,
                             destination: destination,
                             remaining: head.contentLength)
    }

    private func writeUploadBody() {
        guard var state = upload else { return }

        if !buffer.isEmpty {
            let available = buffer
            buffer = Data()
            let count = min(available.count, state.remaining)
            if count > 0 {
                try? state.handle.write(contentsOf: Data(available.prefix(count)))
                state.remaining -= count
                upload = state
            }
        }

        if state.remaining == 0 {
            finishUpload()
        }
    }

    private func finishUpload() {
        guard let state = upload else { return }
        upload = nil

        do {
            try state.handle.close()
            let folder = state.destination.deletingLastPathComponent()
            let name = state.destination.lastPathComponent
            let destination = FileStore.uniqueDestination(in: folder, name: name)
            try FileManager.default.moveItem(at: state.tempURL, to: destination)
            send(.json(["ok": true, "name": destination.lastPathComponent]))
        } catch {
            try? FileManager.default.removeItem(at: state.tempURL)
            send(.error(500, "保存文件失败"))
        }
    }

    private func cleanupUpload(fail: Bool) {
        guard let state = upload else { return }
        upload = nil
        try? state.handle.close()
        if fail {
            try? FileManager.default.removeItem(at: state.tempURL)
        }
    }

    // MARK: - 发送

    private func send(_ response: HTTPResponse) {
        isSending = true
        let data = response.serialized()
        connection.send(content: data,
                        contentContext: .defaultMessage,
                        isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func sendDownload(_ plan: DownloadPlan, headOnly: Bool) {
        isSending = true
        guard let handle = try? FileHandle(forReadingFrom: plan.fileURL) else {
            send(.error(500, "无法读取文件"))
            return
        }

        var header = "HTTP/1.1 \(plan.isPartial ? 206 : 200) \(plan.isPartial ? "Partial Content" : "OK")\r\n"
        header += "Server: WiFiDrop\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Content-Type: \(plan.contentType)\r\n"
        header += "Content-Length: \(plan.length)\r\n"
        if plan.isPartial {
            header += "Content-Range: bytes \(plan.offset)-\(plan.offset + plan.length - 1)/\(plan.totalLength)\r\n"
        }
        let fileName = plan.fileURL.lastPathComponent
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "download"
        header += "Content-Disposition: attachment; filename*=UTF-8''\(encoded)\r\n"
        header += "\r\n"

        let headerData = Data(header.utf8)

        if headOnly {
            try? handle.close()
            connection.send(content: headerData,
                            contentContext: .defaultMessage,
                            isComplete: true,
                            completion: .contentProcessed { [weak self] _ in
                self?.close()
            })
            return
        }

        handle.seek(toFileOffset: UInt64(max(0, plan.offset)))
        connection.send(content: headerData,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { [weak self] error in
            guard let self else {
                try? handle.close()
                return
            }
            if error != nil {
                try? handle.close()
                self.close()
                return
            }
            self.streamFile(handle: handle, remaining: plan.length)
        })
    }

    private func streamFile(handle: FileHandle, remaining: Int64) {
        guard !isClosed else {
            try? handle.close()
            return
        }
        guard remaining > 0 else {
            try? handle.close()
            finishSending()
            return
        }

        let chunkSize = Int(min(Int64(256 * 1024), remaining))
        let chunk = handle.readData(ofLength: chunkSize)
        guard !chunk.isEmpty else {
            try? handle.close()
            finishSending()
            return
        }

        connection.send(content: chunk,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { [weak self] error in
            guard let self else {
                try? handle.close()
                return
            }
            if error != nil {
                try? handle.close()
                self.close()
                return
            }
            self.streamFile(handle: handle, remaining: remaining - Int64(chunk.count))
        })
    }

    private func finishSending() {
        connection.send(content: nil,
                        contentContext: .defaultMessage,
                        isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    // MARK: - 关闭

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        cleanupUpload(fail: true)
        onClose?()
        onClose = nil
    }
}
