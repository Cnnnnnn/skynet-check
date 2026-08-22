import AppKit
import SkynetMonitorCore
import SwiftUI

// Panel card for skill/MCP upgrade detection. Detection only: the actions
// hand the upgrade to the official CLI commands instead of the app writing
// to configs or node_modules itself.
struct ComponentUpdateCardView: View {
    let phase: ComponentUpdatePhase
    let skillReport: SkillUpdateReport?
    let skillFailureDetail: String?
    let mcpFindings: [McpVersionFinding]
    let checkedAt: Date?
    let onRecheck: () -> Void

    @State private var isExpanded = false
    @State private var isMoreExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                contentRows
                Button("重新检查") {
                    onRecheck()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Label(
                    MonitorText.ComponentUpdate.cardTitle,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.subheadline.weight(.semibold))
                if let badge = badgeText {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var badgeText: String? {
        switch phase {
        case .checking:
            return nil
        case .idle, .needsLogin, .failed:
            return nil
        case .completed:
            let outdatedSkills = skillReport?.updates.count ?? 0
            let upgradableMCPs = mcpFindings.filter(\.isUpgradable).count
            guard outdatedSkills > 0 || upgradableMCPs > 0 else {
                return MonitorText.UpdateCheck.upToDate
            }
            var parts: [String] = []
            if outdatedSkills > 0 {
                parts.append("Skill \(outdatedSkills)")
            }
            if upgradableMCPs > 0 {
                parts.append("MCP \(upgradableMCPs)")
            }
            return parts.joined(separator: " · ") + " \(MonitorText.ComponentUpdate.upgradableSuffix)"
        }
    }

    @ViewBuilder
    private var contentRows: some View {
        statusRow
        skillRows
        mcpRows
        pinUpgradeRow
        if let checkedAt {
            Label(
                MonitorText.ComponentUpdate.lastChecked(
                    checkedAt.formatted(date: .omitted, time: .shortened)
                ),
                systemImage: "clock"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        Button("重新检查") {
            onRecheck()
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    // Status text sits above the (possibly stale) data: a fresh check in
    // flight or a failure does not hide the last known list.
    @ViewBuilder
    private var statusRow: some View {
        switch phase {
        case .checking:
            Text(MonitorText.ComponentUpdate.checking)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .needsLogin:
            Text(MonitorText.ComponentUpdate.needsLogin)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            VStack(alignment: .leading, spacing: 2) {
                Text(MonitorText.ComponentUpdate.failed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let skillFailureDetail, !skillFailureDetail.isEmpty {
                    Text("\(MonitorText.ComponentUpdate.failureReasonPrefix)\(skillFailureDetail)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        case .idle, .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var skillRows: some View {
        if let report = skillReport {
            sectionHeader(
                MonitorText.ComponentUpdate.skillSection,
                detail: report.updates.isEmpty
                    ? MonitorText.ComponentUpdate.skillAllCurrent(report.totalChecked)
                    : MonitorText.ComponentUpdate.skillOutdated(
                        report.updates.count,
                        total: report.totalChecked
                    ),
                warning: !report.updates.isEmpty
            )
            ForEach(report.updates.prefix(3)) { update in
                changeRow(
                    title: update.name,
                    from: update.installedVersion,
                    to: update.latestVersion
                )
            }
            if report.updates.count > 3 {
                moreSkillsDisclosure(remaining: Array(report.updates.dropFirst(3)))
            }
            if !report.updates.isEmpty {
                UpgradeActionRow(
                    title: MonitorText.ComponentUpdate.skillUpgradeTitle(
                        report.updates.count
                    ),
                    detail: nil,
                    primaryLabel: "用 Terminal 升级",
                    primaryCommand: CLIInstallGuide.mcpRepairCommand,
                    fallbackLabel: "复制精确命令",
                    fallbackCommand: CLIInstallGuide.skillUpgradeCommand(
                        names: report.updates.map(\.name)
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var mcpRows: some View {
        if !mcpFindings.isEmpty {
            sectionHeader(
                MonitorText.ComponentUpdate.mcpSection,
                detail: nil,
                warning: mcpFindings.contains(where: \.isUpgradable)
            )
            ForEach(mcpFindings) { finding in
                mcpRow(finding)
            }
            if mcpFindings.contains(where: \.isUpgradable) {
                UpgradeActionRow(
                    title: MonitorText.ComponentUpdate.mcpUpgradeTitle(
                        mcpFindings.filter(\.isUpgradable).count
                    ),
                    detail: nil,
                    primaryLabel: "用 Terminal 升级",
                    primaryCommand: CLIInstallGuide.mcpRepairCommand
                )
            }
        }
    }

    private func moreSkillsDisclosure(remaining: [SkillUpdate]) -> some View {
        DisclosureGroup(isExpanded: $isMoreExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(remaining) { update in
                    changeRow(
                        title: update.name,
                        from: update.installedVersion,
                        to: update.latestVersion
                    )
                }
            }
            .padding(.top, 4)
        } label: {
            Label(
                "查看更多（剩余 \(remaining.count) 个）",
                systemImage: "ellipsis.rectangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // npx-pinned servers keep their version inside the ZCode config; the
    // CLI's update tools cannot edit that file, so the actionable help is
    // the new number and where to paste it.
    @ViewBuilder
    private var pinUpgradeRow: some View {
        if let pinned = mcpFindings.first(where: { $0.isNPXPinned && $0.isUpgradable }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(MonitorText.ComponentUpdate.pinUpgradeTitle(pinned.serverName))
                        .font(.caption)
                }
                Text(
                    MonitorText.ComponentUpdate.pinUpgradeDetail(
                        package: pinned.packageName ?? "",
                        from: pinned.installedVersion ?? "",
                        to: pinned.latestVersion ?? ""
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(
                        MonitorText.ComponentUpdate.copyNewVersion(
                            pinned.latestVersion ?? ""
                        )
                    ) {
                        copyToPasteboard(pinned.latestVersion ?? "")
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
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func revealConfigFile() {
        let configURL = URL(
            fileURLWithPath: ("~/.zcode/cli/config.json" as NSString)
                .expandingTildeInPath
        )
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    private func mcpRow(_ finding: McpVersionFinding) -> some View {
        HStack(spacing: 6) {
            Image(
                systemName: finding.isUpgradable
                    ? "arrow.up.circle.fill" : "checkmark.circle"
            )
            .foregroundStyle(finding.isUpgradable ? .orange : .green)
            .accessibilityHidden(true)
            Text(finding.serverName)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(mcpDetail(finding))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func mcpDetail(_ finding: McpVersionFinding) -> String {
        if finding.unpinned {
            return MonitorText.ComponentUpdate.unpinnedDetail
        }
        guard let installed = finding.installedVersion else {
            return MonitorText.ComponentUpdate.unavailableDetail
        }
        guard let latest = finding.latestVersion else {
            return "\(installed) · \(MonitorText.ComponentUpdate.unavailableDetail)"
        }
        if finding.isUpgradable {
            return "\(installed) → \(latest)"
        }
        return "\(installed) \(MonitorText.UpdateCheck.upToDate)"
    }

    private func sectionHeader(
        _ title: String,
        detail: String?,
        warning: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(warning ? .orange : .secondary)
            }
            Spacer()
        }
    }

    private func changeRow(
        title: String,
        from: String,
        to: String
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text("\(from) → \(to)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

extension SkillUpdate: Identifiable {
    public var id: String { name }
}

extension McpVersionFinding: Identifiable {
    public var id: String { serverName }
}
