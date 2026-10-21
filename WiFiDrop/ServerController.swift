import Foundation
import UIKit
import Combine

/// 管理 HTTP 服务的启动、停止以及对外展示的地址与统计信息。
final class ServerController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var primaryURL: String = ""
    @Published private(set) var alternativeURLs: [String] = []
    @Published private(set) var statusMessage: String = "正在启动…"
    @Published private(set) var fileCount: Int = 0
    @Published private(set) var totalBytes: Int64 = 0

    private let store = FileStore()
    private var server: HTTPServer?
    private let statsQueue = DispatchQueue(label: "com.local.wifidrop.stats", qos: .utility)

    /// 启动服务，默认使用 8080 端口，被占用时自动顺延。
    func start() {
        guard server == nil else { return }
        statusMessage = "正在启动…"

        let server = HTTPServer(router: Router(store: store))
        server.onStateChange = { [weak self] running, port in
            guard let self else { return }
            self.isRunning = running
            if let port {
                self.port = port
                self.updateAddresses()
                self.statusMessage = "服务已开启"
                self.refreshStats()
            } else {
                self.statusMessage = "启动失败，端口可能被占用"
            }
        }
        self.server = server
        server.start(preferredPort: 8080)

        updateAddresses()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// 停止服务并恢复系统自动锁屏。
    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        primaryURL = ""
        alternativeURLs = []
        statusMessage = "服务已停止"
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 从后台回到前台时，若服务已中断则重新启动。
    func restartIfNeeded() {
        guard !isRunning else { return }
        stop()
        start()
    }

    /// 手动刷新地址与文件统计。
    func refresh() {
        updateAddresses()
        refreshStats()
    }

    private func updateAddresses() {
        let addresses = NetworkInfo.localIPv4Addresses()
        guard port > 0, let primary = addresses.first else {
            primaryURL = ""
            alternativeURLs = []
            return
        }
        primaryURL = "http://\(primary):\(port)"
        alternativeURLs = addresses.dropFirst().map { "http://\($0):\(port)" }
    }

    private func refreshStats() {
        statsQueue.async { [weak self] in
            guard let self else { return }
            let stats = self.store.statistics()
            DispatchQueue.main.async {
                self.fileCount = stats.count
                self.totalBytes = stats.bytes
            }
        }
    }
}
