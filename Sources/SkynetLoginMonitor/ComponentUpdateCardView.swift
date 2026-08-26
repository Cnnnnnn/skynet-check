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
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Label(
                    MonitorText.ComponentUpdate.cardTitle,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if let badge = badgeText {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Match the blue cards; only tint when something is actually upgradable
    // so the purple-looking outlier does not read as a layout bug.
    private var cardBackground: Color {
        hasUpgrades ? Color.orange.opacity(0.10) : Color.blue.opacity(0.08)
    }

    private var hasUpgrades: Bool {
        guard case .completed = phase else {
            return false
        }
        let outdatedSkills = skillReport?.updates.count ?? 0
        let upgradableMCPs = mcpFindings.filter(\.isUpgradable).count
        return outdatedSkills > 0 || upgradableMCPs > 0
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
            return MonitorText.ComponentUpdate.upgradableBadge(
                skillCount: outdatedSkills,
                mcpCount: upgradableMCPs
            )
        }
    }

    @ViewBuilder
    private var contentRows: some View {
        statusRow
        skillRows
        mcpRows
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
            let upgradable = mcpFindings.filter(\.isUpgradable)
            if upgradable.count > 1,
               let script = CLIInstallGuide.mcpUpgradeScript(for: upgradable)
            {
                UpgradeActionRow(
                    title: MonitorText.ComponentUpdate.mcpUpgradeTitle(
                        upgradable.count
                    ),
                    detail: nil,
                    primaryLabel: MonitorText.ComponentUpdate.openTerminalUpgrade,
                    primaryCommand: script,
                    fallbackLabel: MonitorText.ComponentUpdate.copyAllUpgradeCommands,
                    fallbackCommand: script
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

    // Generated command rewrites IDE configs via `skynet mcp install`.
    private func mcpRow(_ finding: McpVersionFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(
                    systemName: finding.isUpgradable
                        ? "arrow.up.circle.fill" : "checkmark.circle"
                )
                .foregroundStyle(finding.isUpgradable ? .orange : .green)
                .accessibilityHidden(true)
                Text("\(finding.serverName)（\(finding.configSource)）")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(mcpDetail(finding))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if finding.isUpgradable {
                McpUpgradeCommandRow(finding: finding)
            }
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
            if let node = pinnedNodeHint(finding) {
                return "\(installed) → \(latest) · node \(node)"
            }
            return "\(installed) → \(latest)"
        }
        return "\(installed) \(MonitorText.UpdateCheck.upToDate)"
    }

    private func pinnedNodeHint(_ finding: McpVersionFinding) -> String? {
        guard let command = finding.configuredCommand,
              command.contains("/.nvm/versions/node/")
        else {
            return nil
        }
        let parts = command.split(separator: "/")
        guard let index = parts.firstIndex(of: "node"),
              index + 1 < parts.count
        else {
            return nil
        }
        return String(parts[index + 1])
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
    public var id: String { "\(configSource)-\(serverName)" }
}
