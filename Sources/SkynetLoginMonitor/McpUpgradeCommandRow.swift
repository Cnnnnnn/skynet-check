import AppKit
import SkynetMonitorCore
import SwiftUI

// Per-MCP upgrade actions: copy the generated Terminal command (and optionally
// open Terminal). Prefer npm --prefix / pin bump; `skynet mcp install` is only
// a last-resort fallback for unresolved packages.
struct McpUpgradeCommandRow: View {
    let finding: McpVersionFinding
    var onCommandUsed: (() -> Void)?

    @State private var commandCopied = false

    var body: some View {
        if let command = CLIInstallGuide.mcpUpgradeCommand(for: finding) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(MonitorText.ComponentUpdate.openTerminalUpgrade) {
                        copyToPasteboard(command)
                        onCommandUsed?()
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
                        onCommandUsed?()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                if let expectation = CLIInstallGuide.mcpUpgradeExpectation(
                    for: finding
                ) {
                    Text(expectation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
