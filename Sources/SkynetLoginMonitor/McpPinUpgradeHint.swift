import AppKit
import SkynetMonitorCore
import SwiftUI

// Hint row for npx-pinned MCP servers: the version lives inside the ZCode
// config, which the CLI's update tools cannot edit, so the actionable help
// is the new number and where to paste it.
struct McpPinUpgradeHint: View {
    let finding: McpVersionFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(MonitorText.ComponentUpdate.pinUpgradeTitle(finding.serverName))
                    .font(.caption)
            }
            Text(
                MonitorText.ComponentUpdate.pinUpgradeDetail(
                    package: finding.packageName ?? "",
                    from: finding.installedVersion ?? "",
                    to: finding.latestVersion ?? ""
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(
                    MonitorText.ComponentUpdate.copyNewVersion(
                        finding.latestVersion ?? ""
                    )
                ) {
                    copyToPasteboard(finding.latestVersion ?? "")
                }
                .controlSize(.small)
                Button(MonitorText.ComponentUpdate.revealConfig) {
                    revealConfigFile()
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

    private func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([
            SkynetEndpoints.zcodeConfigURL,
        ])
    }
}
