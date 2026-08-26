import AppKit
import SkynetMonitorCore
import SwiftUI

struct UpgradeActionRow: View {
    let title: String
    let detail: String?
    let primaryLabel: String
    let primaryCommand: String
    var fallbackLabel: String?
    var fallbackCommand: String?
    var expectation: String?

    @State private var commandCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button(primaryLabel) {
                    copyToPasteboard(primaryCommand)
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let fallbackLabel, let fallbackCommand {
                    Button(commandCopied ? "命令已复制" : fallbackLabel) {
                        copyToPasteboard(fallbackCommand)
                        commandCopied = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            if let expectation {
                Text(expectation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct EnvironmentCardView: View {
    let report: EnvironmentReport
    let notificationPermission: NotificationPermissionStatus
    let onRecheck: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(
                    Array(report.checks.enumerated()),
                    id: \.offset
                ) { _, check in
                    checkRow(check)
                }
                if report.isCLIBehindLatest {
                    cliUpgradeRow
                }
                if let outdated = report.mcpConfiguration?.outdatedSkills,
                   !outdated.isEmpty {
                    skillSyncRow(outdatedCount: outdated.count)
                }
                if report.needsMCPRepair {
                    mcpRepairRow
                }
                if notificationPermission.shouldShowInPanel {
                    notificationRow
                    if notificationPermission.needsSettingsShortcut {
                        Button("打开系统设置开启通知") {
                            openNotificationSettings()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                Button("重新检查") {
                    onRecheck()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.top, 6)
        } label: {
            Label("环境诊断", systemImage: "stethoscope")
                .font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var cliUpgradeRow: some View {
        UpgradeActionRow(
            title: "CLI 有新版 \(report.latestCLIVersion ?? "")",
            detail: "当前 \(report.cliVersion ?? "")",
            primaryLabel: "用 Terminal 升级",
            primaryCommand: CLIInstallGuide.updateCommand,
            fallbackLabel: "复制 npm 命令",
            fallbackCommand: CLIInstallGuide.skynetCommand
        )
    }

    private func skillSyncRow(outdatedCount: Int) -> some View {
        UpgradeActionRow(
            title: "\(outdatedCount) 个 Skill 落后于团队基线",
            detail: nil,
            primaryLabel: "用 Terminal 同步",
            primaryCommand: CLIInstallGuide.skillSyncCommand
        )
    }

    private var mcpRepairRow: some View {
        UpgradeActionRow(
            title: "MCP 配置需要修复",
            detail: nil,
            primaryLabel: "用 Terminal 修复",
            primaryCommand: CLIInstallGuide.mcpRepairCommand
        )
    }

    private func checkRow(_ check: EnvironmentCheck) -> some View {
        HStack(spacing: 6) {
            Image(systemName: check.status.symbolName)
                .foregroundStyle(check.status.color)
                .accessibilityHidden(true)
            Text(check.name)
                .font(.caption)
            Spacer()
            Text(check.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var notificationRow: some View {
        HStack(spacing: 6) {
            Image(systemName: notificationPermission.symbolName)
                .foregroundStyle(notificationPermission.color)
                .accessibilityHidden(true)
            Text("通知权限")
                .font(.caption)
            Spacer()
            Text(notificationPermission.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func openNotificationSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension EnvironmentCheckStatus {
    var symbolName: String {
        switch self {
        case .passed:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed:
            .green
        case .warning:
            .orange
        case .failed:
            .red
        }
    }
}

private extension NotificationPermissionStatus {
    var symbolName: String {
        switch self {
        case .authorized:
            "checkmark.circle.fill"
        case .notDetermined:
            "exclamationmark.triangle.fill"
        case .denied:
            "xmark.circle.fill"
        case .unsupported:
            "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .authorized:
            .green
        case .notDetermined:
            .orange
        case .denied:
            .red
        case .unsupported:
            .secondary
        }
    }

    var detail: String {
        switch self {
        case .authorized:
            "通知已授权"
        case .notDetermined:
            "尚未确认授权"
        case .denied:
            "已被拒绝"
        case .unsupported:
            "当前环境不支持通知"
        }
    }
}
