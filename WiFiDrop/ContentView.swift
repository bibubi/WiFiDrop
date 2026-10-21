import SwiftUI
import UIKit

/// 主界面：展示服务地址、二维码与运行状态。
struct ContentView: View {
    @StateObject private var controller = ServerController()
    @Environment(\.scenePhase) private var scenePhase

    private let accent = Color(red: 0.0, green: 0.44, blue: 0.89)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                addressCard

                if controller.isRunning, !controller.primaryURL.isEmpty {
                    QRCodeView(text: controller.primaryURL)
                }

                statsRow
                actionButton
                tips
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { controller.start() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                controller.restartIfNeeded()
            case .background:
                controller.stop()
            default:
                break
            }
        }
    }

    // MARK: - 子视图

    private var header: some View {
        VStack(spacing: 6) {
            Text("局域网传输")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(controller.statusMessage)
                .font(.system(size: 14))
                .foregroundColor(controller.isRunning ? Color(red: 0.13, green: 0.63, blue: 0.35) : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var addressCard: some View {
        VStack(spacing: 14) {
            Text("在同一 WiFi 下的设备浏览器中打开")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(controller.primaryURL.isEmpty ? "正在获取地址…" : controller.primaryURL)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)

            Button(action: copyAddress) {
                Text("复制地址")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(accent)
                    .clipShape(Capsule())
            }
            .disabled(controller.primaryURL.isEmpty)

            if !controller.alternativeURLs.isEmpty {
                VStack(spacing: 3) {
                    Text("其他网络地址")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    ForEach(controller.alternativeURLs, id: \.self) { url in
                        Text(url)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "文件数量", value: "\(controller.fileCount)")
            statCard(title: "占用空间", value: ByteCountFormatter.string(fromByteCount: controller.totalBytes,
                                                                     countStyle: .file))
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionButton: some View {
        Button(action: toggleServer) {
            Text(controller.isRunning ? "停止服务" : "启动服务")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(controller.isRunning ? Color(red: 0.85, green: 0.20, blue: 0.18) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(controller.isRunning ? Color.white : accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(controller.isRunning ? Color(red: 0.95, green: 0.80, blue: 0.79) : Color.clear,
                                lineWidth: 1)
                )
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            tipRow("手机与电脑需连接同一个 WiFi / 热点")
            tipRow("App 需保持在前台，锁屏后服务会暂停")
            tipRow("若提示启动失败，请到「设置 → 隐私与安全性 → 本地网络」允许本 App")
            tipRow("上传的文件保存在 App 的「文件」目录中")
            tipRow("网页端支持上传、下载、新建文件夹与删除")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent.opacity(0.35))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 行为

    private func copyAddress() {
        UIPasteboard.general.string = controller.primaryURL
    }

    private func toggleServer() {
        if controller.isRunning {
            controller.stop()
        } else {
            controller.restartIfNeeded()
        }
    }
}
