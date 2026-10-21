import Foundation
import UniformTypeIdentifiers

/// 路由器对请求的处理结果。
enum RouteAction {
    case respond(HTTPResponse)
    case upload(UploadPlan)
    case download(DownloadPlan)
}

/// 流式上传计划。
struct UploadPlan {
    let destinationDirectory: URL
    let fileName: String
}

/// 文件下载计划（支持单段 Range）。
struct DownloadPlan {
    let fileURL: URL
    let offset: Int64
    let length: Int64
    let totalLength: Int64
    let contentType: String
    let isPartial: Bool
}

/// 将 HTTP 请求映射为具体动作。
final class Router {
    private let store: FileStore

    init(store: FileStore) {
        self.store = store
    }

    func route(_ head: HTTPRequestHead) -> RouteAction {
        switch (head.method, head.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return .respond(.html(WebPage.index))

        case ("GET", "/api/list"):
            return listAction(path: head.query["path"] ?? "")

        case ("POST", "/api/mkdir"):
            return makeDirectoryAction(head)

        case ("POST", "/api/delete"):
            return deleteAction(head)

        case ("POST", "/api/upload"), ("PUT", "/api/upload"):
            return uploadAction(head)

        case ("GET", let path) where path.hasPrefix("/files/"):
            return downloadAction(rawPath: String(path.dropFirst("/files/".count)),
                                  rangeHeader: head.headers["range"])

        case ("HEAD", let path) where path.hasPrefix("/files/"):
            return downloadAction(rawPath: String(path.dropFirst("/files/".count)),
                                  rangeHeader: head.headers["range"])

        case ("GET", "/favicon.ico"):
            return .respond(HTTPResponse(status: 204))

        default:
            return .respond(.error(404, "接口不存在"))
        }
    }

    // MARK: - 动作构建

    private func listAction(path: String) -> RouteAction {
        do {
            let entries = try store.list(path)
            let payload: [String: Any] = [
                "ok": true,
                "path": path,
                "free": store.freeSpace(),
                "entries": entries.map { entry -> [String: Any] in
                    [
                        "name": entry.name,
                        "path": entry.path,
                        "dir": entry.isDirectory,
                        "size": entry.size,
                        "mtime": entry.modified
                    ]
                }
            ]
            return .respond(.json(payload))
        } catch {
            return .respond(.error(404, error.localizedDescription))
        }
    }

    private func makeDirectoryAction(_ head: HTTPRequestHead) -> RouteAction {
        let parentPath = head.query["path"] ?? ""
        guard let rawName = head.query["name"], let name = FileStore.sanitize(name: rawName) else {
            return .respond(.error(400, "文件夹名称不合法"))
        }
        guard let parent = store.resolve(parentPath, allowRoot: true) else {
            return .respond(.error(400, "路径不合法"))
        }
        let target = parent.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return .respond(.json(["ok": true, "name": name]))
        } catch {
            return .respond(.error(500, error.localizedDescription))
        }
    }

    private func deleteAction(_ head: HTTPRequestHead) -> RouteAction {
        guard let path = head.query["path"], !path.isEmpty else {
            return .respond(.error(400, "缺少路径"))
        }
        do {
            try store.delete(path)
            return .respond(.json(["ok": true]))
        } catch {
            return .respond(.error(404, error.localizedDescription))
        }
    }

    private func uploadAction(_ head: HTTPRequestHead) -> RouteAction {
        guard head.contentLength > 0 else {
            return .respond(.error(411, "需要 Content-Length"))
        }
        guard let folder = store.resolve(head.query["path"] ?? "", allowRoot: true) else {
            return .respond(.error(400, "路径不合法"))
        }
        guard let rawName = head.query["name"], let name = FileStore.sanitize(name: rawName) else {
            return .respond(.error(400, "文件名不合法"))
        }
        return .upload(UploadPlan(destinationDirectory: folder, fileName: name))
    }

    private func downloadAction(rawPath: String, rangeHeader: String?) -> RouteAction {
        guard let url = store.resolve(rawPath) else {
            return .respond(.error(403, "路径不合法"))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .respond(.error(404, "文件不存在"))
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let total = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        var offset: Int64 = 0
        var length = total
        var partial = false

        if let rangeHeader, rangeHeader.hasPrefix("bytes="), total > 0 {
            let spec = rangeHeader.dropFirst("bytes=".count)
            let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if bounds.count == 2 {
                let startText = String(bounds[0])
                let endText = String(bounds[1])
                if let start = Int64(startText), start >= 0, start < total {
                    offset = start
                    if let end = Int64(endText) {
                        length = min(end, total - 1) - start + 1
                    } else {
                        length = total - start
                    }
                    partial = true
                } else if startText.isEmpty, let suffix = Int64(endText), suffix > 0 {
                    length = min(suffix, total)
                    offset = total - length
                    partial = true
                }
            }
        }

        return .download(DownloadPlan(
            fileURL: url,
            offset: offset,
            length: length,
            totalLength: total,
            contentType: Router.mimeType(for: url),
            isPartial: partial
        ))
    }

    /// 根据扩展名推断 MIME 类型。
    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
