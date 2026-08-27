import AppKit
import SkynetMonitorCore
import SwiftUI

@MainActor
struct MenuBarView: View {
    @ObservedObject private var store: MonitorStore
    private let launchAtLogin: any LaunchAtLoginControlling
    private let muteStore: NotificationMuteStore

    @State private var diagnosticsCopied = false
    // MenuBarExtra + ScrollView needs an explicit height; maxHeight alone
    // collapses the window to a flat strip. Measure content, then clamp.
    @State private var contentHeight: CGFloat = 0

    init(
        store: MonitorStore,
        launchAtLogin: any LaunchAtLoginControlling,
        muteStore: NotificationMuteStore
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        self.muteStore = muteStore
    }

    var body: some View {
        let presentation = store.state.presentation

        ScrollView(.vertical) {
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
                            "最近：\(lastCompletedState.presentation.title) · "
                                + lastCheckedAt.formatted(date: .omitted, time: .shortened),
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
                            "平均会话 \(DurationPresentation.summarize(sessionStatistics.average))"
                                + "（近 \(sessionStatistics.observationCount) 次）",
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

                if store.showsComponentUpdates {
                    ComponentUpdateCardView(
                        phase: store.skillUpdatePhase,
                        skillReport: store.skillUpdateReport,
                        skillFailureDetail: store.skillUpdateFailureDetail,
                        mcpFindings: store.mcpVersionFindings,
                        checkedAt: store.componentUpdateCheckedAt,
                        onRecheck: { Task { await store.checkComponentUpdates() } },
                        onUpgradeCommandUsed: {
                            store.noteComponentUpgradeCommandUsed()
                        }
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

                SettingsSectionView(
                    store: store,
                    launchAtLogin: launchAtLogin,
                    muteStore: muteStore
                )

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
            .padding(16)
            .frame(width: 320, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PanelContentHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            Task { @MainActor in
                guard height > 0, abs(height - contentHeight) > 0.5 else {
                    return
                }
                contentHeight = height
            }
        }
        .frame(width: 320)
        .frame(height: panelViewportHeight)
        .background(.regularMaterial)
        .onAppear {
            Task { await store.recheckComponentsIfUpgradePending() }
        }
    }

    // Explicit height (not maxHeight): short content keeps a tight panel;
    // tall content clamps and the ScrollView becomes scrollable.
    private var panelViewportHeight: CGFloat {
        let maxHeight = Self.panelMaxHeight
        guard contentHeight > 0 else {
            return min(420, maxHeight)
        }
        return min(contentHeight, maxHeight)
    }

    private static var panelMaxHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 700
        return min(640, max(360, visible * 0.7))
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
}

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
