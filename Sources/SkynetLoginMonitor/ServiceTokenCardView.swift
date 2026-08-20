import AppKit
import SkynetMonitorCore
import SwiftUI

struct ServiceTokenCardView: View {
    let tokens: [ServiceToken]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("服务 Token", systemImage: "key")
                .font(.subheadline.weight(.semibold))
            Text("仅本机显示，复制后可粘贴到需要的位置。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(tokens, id: \.key) { token in
                TokenRow(token: token)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct TokenRow: View {
    let token: ServiceToken

    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(token.displayName)
                .font(.caption)
            Text(token.maskedValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button(copied ? "已复制" : "复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(token.value, forType: .string)
                copied = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}
