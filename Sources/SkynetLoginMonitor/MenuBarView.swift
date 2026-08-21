import AppKit
import SkynetMonitorCore
import SwiftUI

@MainActor
struct MenuBarView: View {
    @ObservedObject private var store: MonitorStore
    private let launchAtLogin: any LaunchAtLoginControlling

    @State private var launchAtLoginEnabled: Bool
    @State private var launchAtLoginMessage: String?
    @State private var diagnosticsCopied = false
    @State private var isSettingsExpanded = false

    init(
        store: MonitorStore,
        launchAtLogin: any LaunchAtLoginControlling
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        _launchAtLoginEnabled = State(initialValue: launchAtLogin.isEnabled)
    }

    var body: some View {
        let presentation = store.state.presentation

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(presentation.tint.color)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Skynet")
                        .font(.headline)
                    Text(presentation.title)
                        .font(.subheadline)
                        .foregroundStyle(presentation.tint.color)
                }

                Spacer(minLength: 12)

                if store.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Skynet \(presentation.title)")

            if let email = store.state.authenticatedEmail {
                Label(email, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Text(MonitorText.SessionExpiry.scopeCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                if let cliVersion = store.cliVersion {
                    Label("CLI \(cliVersion)", systemImage: "terminal")
                }
                if let lastCheckedAt = store.lastCheckedAt,
                   let lastCompletedState = store.lastCompletedState {
                    Label(
                        "最近：\(lastCompletedState.presentation.title) · \(lastCheckedAt.formatted(date: .omitted, time: .shortened))",
                        systemImage: "clock"
                    )
                }
                if let nextAutomaticCheckAt = store.nextAutomaticCheckAt {
                    Label(
                        "下次自动检查：\(nextAutomaticCheckAt.formatted(date: .omitted, time: .shortened))",
                        systemImage: "timer"
                    )
                }
                if let sessionExpiresAt = store.sessionExpiresAt {
                    Label(
                        SessionExpiryPresentation.panelLabel(expiresAt: sessionExpiresAt),
                        systemImage: "clock.badge.exclamationmark"
                    )
                } else if store.sessionExpiryOutlived {
                    Label(
                        MonitorText.SessionExpiry.panelOutlived,
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if let sessionStatistics = store.sessionStatistics {
                    Label(
                        "平均会话 \(DurationPresentation.summarize(sessionStatistics.average))（近 \(sessionStatistics.observationCount) 次）",
                        systemImage: "chart.bar"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            if store.state == .cliMissing {
                MissingCLICardView(
                    isChecking: store.isChecking,
                    onRefresh: { Task { await store.refresh() } }
                )
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await store.refresh(notifyResult: true) }
                    } label: {
                        Label("立即检查", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isChecking)

                    Button {
                        Task { await store.login() }
                    } label: {
                        Label("重新登录", systemImage: "person.crop.circle.badge.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.isChecking)
                }
            }

            if case let .serviceError(message) = store.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let loginURL = store.loginURL, !store.state.isAuthenticated {
                Button {
                    NSWorkspace.shared.open(loginURL)
                } label: {
                    Label("打开登录页面", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let environmentReport = store.environmentReport {
                EnvironmentCardView(
                    report: environmentReport,
                    notificationPermission: store.notificationPermission,
                    onRecheck: { Task { await store.inspectEnvironment() } }
                )
            }

            if !store.serviceTokens.isEmpty {
                ServiceTokenCardView(
                    tokens: store.serviceTokens,
                    validation: store.tokenValidation
                )
            }

            if store.permissionAudit.needsRepair {
                PermissionCardView(
                    repairMessage: store.permissionRepairMessage,
                    onRepair: { store.repairPermissions() }
                )
            }

            Divider()

            DisclosureGroup(isExpanded: $isSettingsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("开机启动", systemImage: "power")
                            .font(.subheadline)
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { launchAtLoginEnabled },
                                set: { enabled in setLaunchAtLogin(enabled) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel(Text("开机启动"))
                    }

                    HStack(spacing: 10) {
                        Label("自动检查", systemImage: "timer")
                            .font(.subheadline)
                        Slider(
                            value: pollingIntervalBinding,
                            in: 3.0...60.0,
                            step: 1
                        )
                        .accessibilityLabel(Text("自动检查间隔"))
                        .accessibilityValue(Text("\(store.pollingIntervalMinutes) 分钟"))
                        Text("\(store.pollingIntervalMinutes) 分钟")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }

                    updateCheckRow

                    if launchAtLogin.requiresApproval {
                        Text("需要在“系统设置 → 登录项”中允许")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let launchAtLoginMessage {
                        Text(launchAtLoginMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("重置会话统计") {
                            store.resetSessionStatistics()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
            }

            HStack {
                Text("Skynet Login Monitor \(appVersionText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(diagnosticsCopied ? "已复制" : "复制诊断") {
                    copyDiagnostics()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button("退出") {
                    store.stop()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .frame(width: 320)
        .padding(16)
        .background(.regularMaterial)
    }

    private var appVersionText: String {
        guard let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty
        else {
            return ""
        }
        return version
    }

    @ViewBuilder
    private var updateCheckRow: some View {
        HStack(spacing: 8) {
            Button("检查更新") {
                Task { await store.checkForUpdates() }
            }
            .controlSize(.small)
            .disabled(store.updateStatus == .checking)

            switch store.updateStatus {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView()
                    .controlSize(.mini)
            case .upToDate:
                Text(MonitorText.UpdateCheck.upToDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .available(let version):
                Text("有新版本 \(version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let update = store.availableUpdate {
                    Button("前往下载") {
                        NSWorkspace.shared.open(update.downloadURL)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            case .failed:
                Text(MonitorText.UpdateCheck.failed)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pollingIntervalBinding: Binding<Double> {
        Binding(
            get: { Double(store.pollingIntervalMinutes) },
            set: { value in
                store.setPollingInterval(Int(value.rounded()))
            }
        )
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            store.diagnosticsReport(),
            forType: .string
        )
        diagnosticsCopied = true
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLogin.isEnabled
            launchAtLoginMessage = launchAtLogin.requiresApproval
                ? "请在系统设置中批准后再检查"
                : nil
        } catch {
            launchAtLoginEnabled = launchAtLogin.isEnabled
            launchAtLoginMessage = "无法更新开机启动设置"
        }
    }
}

private extension StatusTint {
    var color: Color {
        switch self {
        case .secondary:
            .secondary
        case .green:
            .green
        case .red:
            .red
        case .yellow:
            .yellow
        }
    }
}
