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
    @State private var isMoreMcpExpanded = false

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
            Text(MonitorText.ComponentUpdate.skillSectionCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                    || mcpFindings.contains(where: \.hasNvmNodeMismatch)
            )
            Text(MonitorText.ComponentUpdate.mcpSectionCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            // MenuBarExtra cannot host a root ScrollView reliably; keep the
            // panel intrinsic height and tuck long MCP lists behind disclosure
            // the same way skills already do.
            ForEach(mcpFindings.prefix(3)) { finding in
                mcpRow(finding)
            }
            if mcpFindings.count > 3 {
                moreMcpsDisclosure(remaining: Array(mcpFindings.dropFirst(3)))
            }
            ForEach(
                CLIInstallGuide.mcpRetargetNvmFindings(from: mcpFindings)
            ) { finding in
                if let command = CLIInstallGuide.mcpRetargetNvmCommand(
                    for: finding
                ),
                   let from = finding.configuredNvmNode,
                   let to = finding.pathNvmNode
                {
                    UpgradeActionRow(
                        title: "\(finding.configSource) Node \(from) → \(to)",
                        detail: nil,
                        primaryLabel: MonitorText.ComponentUpdate.copyRetargetNvm,
                        primaryCommand: command,
                        expectation: MonitorText.ComponentUpdate
                            .upgradeExpectRetargetNvm
                    )
                }
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
                    fallbackCommand: script,
                    expectation: MonitorText.ComponentUpdate.upgradeExpectBulk
                )
            }
        }
    }

    private func moreMcpsDisclosure(remaining: [McpVersionFinding]) -> some View {
        DisclosureGroup(isExpanded: $isMoreMcpExpanded) {
            // Fixed-height nested scroll is OK; a root ScrollView is not —
            // MenuBarExtra sizes root ScrollView ideal height to a flat strip.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(remaining) { finding in
                        mcpRow(finding)
                    }
                }
            }
            .frame(height: min(240, CGFloat(remaining.count) * 72))
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

    // Pasteable command: pin bump / npm --prefix / last-resort skynet install.
    private func mcpRow(_ finding: McpVersionFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(
                    systemName: finding.isUpgradable
                        ? "arrow.up.circle.fill" : "checkmark.circle"
                )
                .foregroundStyle(finding.isUpgradable ? .orange : .green)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.serverName)
                        .font(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.configSource)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 6)
                Text(mcpDetail(finding))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
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
        let mismatch = nvmMismatchSuffix(finding)
        if finding.configuredBinaryMissing {
            let node = finding.configuredNvmNode.map { "node \($0)" } ?? "配置路径"
            if let installed = finding.installedVersion,
               let latest = finding.latestVersion
            {
                return joinDetail("\(node) 缺失", mismatch, "\(installed) → \(latest)")
            }
            if let latest = finding.latestVersion {
                return joinDetail("\(node) 缺失", mismatch, "安装 \(latest)")
            }
            return joinDetail("\(node) 缺失", mismatch, nil)
        }
        guard let installed = finding.installedVersion else {
            return joinDetail(
                MonitorText.ComponentUpdate.unavailableDetail,
                mismatch,
                nil
            )
        }
        guard let latest = finding.latestVersion else {
            return joinDetail(
                "\(installed) · \(MonitorText.ComponentUpdate.unavailableDetail)",
                mismatch,
                nil
            )
        }
        if finding.isUpgradable {
            return joinDetail("\(installed) → \(latest)", mismatch, nil)
        }
        return joinDetail(
            "\(installed) \(MonitorText.UpdateCheck.upToDate)",
            mismatch,
            nil
        )
    }

    private func nvmMismatchSuffix(_ finding: McpVersionFinding) -> String? {
        guard let configured = finding.configuredNvmNode,
              let path = finding.pathNvmNode
        else {
            return nil
        }
        return MonitorText.ComponentUpdate.nvmMismatchDetail(
            configured: configured,
            path: path
        )
    }

    private func joinDetail(
        _ head: String,
        _ middle: String?,
        _ tail: String?
    ) -> String {
        [head, middle, tail].compactMap { $0 }.joined(separator: " · ")
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
