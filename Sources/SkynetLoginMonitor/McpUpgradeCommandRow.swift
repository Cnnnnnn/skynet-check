import AppKit
import SkynetMonitorCore
import SwiftUI

// Per-MCP upgrade actions: copy the generated Terminal command (and optionally
// open Terminal). Prefer npm --prefix / pin bump; `skynet mcp install` is only
// a last-resort fallback for unresolved packages.
struct McpUpgradeCommandRow: View {
    let finding: McpVersionFinding

    @State private var commandCopied = false

    var body: some View {
        if let command = CLIInstallGuide.mcpUpgradeCommand(for: finding) {
            HStack(spacing: 8) {
                Button(MonitorText.ComponentUpdate.openTerminalUpgrade) {
                    copyToPasteboard(command)
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(
                    commandCopied
                        ? "命令已复制"
                        : MonitorText.ComponentUpdate.copyUpgradeCommand
                ) {
                    copyToPasteboard(command)
                    commandCopied = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
