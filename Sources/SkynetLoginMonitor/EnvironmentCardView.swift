import AppKit
import SkynetMonitorCore
import SwiftUI

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
