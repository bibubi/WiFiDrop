import Foundation

/// 文件系统操作错误。
enum FileStoreError: LocalizedError {
    case invalidPath
    case notFound
    case notDirectory

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "路径不合法"
        case .notFound: return "文件或目录不存在"
        case .notDirectory: return "该路径不是目录"
        }
    }
}

/// 管理 App 沙盒 Documents 目录中的文件。
///
/// 所有对外暴露的路径都是相对于 Documents 的相对路径，
/// 解析时会拦截 `..`、空字节等越权写法。
final class FileStore {
    let root: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.standardizedFileURL
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 将相对路径解析为沙盒内的绝对路径。
    /// - Parameters:
    ///   - relativePath: 以 `/` 分隔的相对路径。
    ///   - allowRoot: 空路径是否允许解析为根目录。
    func resolve(_ relativePath: String, allowRoot: Bool = false) -> URL? {
        var components: [String] = []
        for part in relativePath.split(separator: "/", omittingEmptySubsequences: true) {
            let name = String(part)
            if name == "." { continue }
            if name == ".." { return nil }
            if name.contains("\0") { return nil }
            components.append(name)
        }
        if components.isEmpty {
            return allowRoot ? root : nil
        }
        let url = components.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { return nil }
        return url
    }

    /// 目录中的一项。
    struct Entry {
        let name: String
        let path: String
        let isDirectory: Bool
        let size: Int64
        let modified: TimeInterval
    }

    /// 列出目录内容，文件夹排在前面并按名称升序。
    func list(_ relativePath: String) throws -> [Entry] {
        guard let directory = resolve(relativePath, allowRoot: true) else {
            throw FileStoreError.invalidPath
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            throw FileStoreError.notFound
        }
        guard isDirectory.boolValue else { throw FileStoreError.notDirectory }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        let base = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var entries: [Entry] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            entries.append(Entry(
                name: name,
                path: base.isEmpty ? name : base + "/" + name,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            ))
        }
        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return entries
    }

    /// 校验用户提交的文件 / 文件夹名称。
    static func sanitize(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return nil }
        guard !trimmed.contains("/"), !trimmed.contains("\\") else { return nil }
        guard !trimmed.contains("\0") else { return nil }
        guard trimmed.utf8.count <= 255 else { return nil }
        return trimmed
    }

    /// 在目标目录中生成不冲突的文件名，重复时追加序号。
    static func uniqueDestination(in directory: URL, name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let renamed = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(renamed)
            index += 1
        }
        return candidate
    }

    /// 删除文件或整个目录。
    func delete(_ relativePath: String) throws {
        guard let url = resolve(relativePath), url.path != root.path else {
            throw FileStoreError.invalidPath
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileStoreError.notFound
        }
        try FileManager.default.removeItem(at: url)
    }

    /// 统计文件数量与总大小。
    func statistics() -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                count += 1
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        return (count, bytes)
    }

    /// 当前可用磁盘空间。
    func freeSpace() -> Int64 {
        if let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        let fallback = try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(fallback?.volumeAvailableCapacity ?? 0)
    }
}
