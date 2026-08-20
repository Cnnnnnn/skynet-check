import AppKit
import SkynetMonitorCore
import SwiftUI

struct MissingCLICardView: View {
    let isChecking: Bool
    let onRefresh: () -> Void

    @State private var installCommandCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要先安装 Skynet CLI", systemImage: "shippingbox")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("复制命令后粘贴到 Terminal 执行，完成后回来重新检测。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CLIInstallGuide.combinedCommand)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 8) {
                Button("复制命令") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        CLIInstallGuide.combinedCommand,
                        forType: .string
                    )
                    installCommandCopied = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("打开 Terminal") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        CLIInstallGuide.combinedCommand,
                        forType: .string
                    )
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("重新检测") {
                    onRefresh()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isChecking)
            }

            if installCommandCopied {
                Text("安装命令已复制")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
