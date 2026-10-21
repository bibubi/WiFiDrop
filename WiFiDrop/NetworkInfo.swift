import Foundation

/// 获取本机局域网 IPv4 地址。
enum NetworkInfo {
    /// 返回去重后的局域网地址，Wi‑Fi 接口（en0）优先。
    static func localIPv4Addresses() -> [String] {
        var collected: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }

            guard let socketAddress = entry.pointee.ifa_addr else { continue }
            guard socketAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            guard name != "lo0" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(socketAddress,
                                     socklen_t(socketAddress.pointee.sa_len),
                                     &host,
                                     socklen_t(host.count),
                                     nil,
                                     0,
                                     NI_NUMERICHOST)
            guard result == 0 else { continue }

            let address = String(cString: host)
            guard !address.isEmpty, !address.hasPrefix("169.254.") else { continue }
            collected.append((name, address))
        }

        collected.sort { lhs, rhs in
            if lhs.name == "en0" && rhs.name != "en0" { return true }
            if rhs.name == "en0" && lhs.name != "en0" { return false }
            return lhs.name < rhs.name
        }

        var unique: [String] = []
        for item in collected where !unique.contains(item.address) {
            unique.append(item.address)
        }
        return unique
    }
}
