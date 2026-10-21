import Foundation
import Network

/// 主动触发 iOS 的「本地网络」权限弹窗。
///
/// iOS 14 起，访问局域网需要用户授权。仅创建监听端口通常不会弹出授权框，
/// 这里用一次短时的 Bonjour 浏览来触发系统提示，浏览本身不参与文件传输。
final class NetworkPermissionRequester {
    private let queue = DispatchQueue(label: "com.local.wifidrop.permission")
    private var browser: NWBrowser?

    /// 发起一次权限请求，5 秒后自动停止浏览。
    func request() {
        guard browser == nil else { return }

        let browser = NWBrowser(for: .bonjour(type: "_wifidrop._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.browser = nil
            default:
                break
            }
        }
        browser.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.browser?.cancel()
            self.browser = nil
        }
    }
}
