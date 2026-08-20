import SkynetMonitorCore
import SwiftUI

struct PermissionCardView: View {
    let repairMessage: String?
    let onRepair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("配置权限过宽", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("session.json 和 config.json 建议仅当前用户可读写。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("修复权限") {
                    onRepair()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                if let repairMessage {
                    Text(repairMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
