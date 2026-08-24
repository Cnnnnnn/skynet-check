import AppKit
import SkynetMonitorCore
import SwiftUI

// The collapsible settings block at the bottom of the menu bar panel:
// launch-at-login, polling interval, app update check, session stats reset.
@MainActor
struct SettingsSectionView: View {
    @ObservedObject var store: MonitorStore
    let launchAtLogin: any LaunchAtLoginControlling
    let muteStore: NotificationMuteStore

    @State private var launchAtLoginEnabled: Bool
    @State private var launchAtLoginMessage: String?
    @State private var isExpanded = false
    @AppStorage("menuBarShowsCountdown") private var showCountdown = false
    // Bumping this re-reads the mute store so the row reflects pause/resume.
    @State private var refreshTick = 0

    init(
        store: MonitorStore,
        launchAtLogin: any LaunchAtLoginControlling,
        muteStore: NotificationMuteStore = NotificationMuteStore()
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        self.muteStore = muteStore
        _launchAtLoginEnabled = State(initialValue: launchAtLogin.isEnabled)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                launchAtLoginRow
                pollingIntervalRow
                countdownToggleRow
                muteRow
                if store.showsUpdateCheck {
                    updateCheckRow
                }
                launchAtLoginHints
                resetStatisticsRow
            }
            .padding(.top, 6)
        } label: {
            Label("设置", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
        }
    }

    // Do-not-disturb: while paused, notifications are dropped (checks and
    // the panel keep updating). Presets cover a meeting through an afternoon.
    private var muteRow: some View {
        HStack(spacing: 8) {
            if let pausedUntil = muteStore.load()?.pausedUntil {
                Label(
                    "通知已暂停至 \(pausedUntil.formatted(date: .omitted, time: .shortened))",
                    systemImage: "bell.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("恢复") {
                    muteStore.resume()
                    refreshTick += 1
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                Menu {
                    ForEach(NotificationMuteWindow.presets, id: \.self) { minutes in
                        Button(Self.muteLabel(minutes)) {
                            muteStore.pause(until: Date().addingTimeInterval(minutes * 60))
                            refreshTick += 1
                        }
                    }
                } label: {
                    Label("暂停通知", systemImage: "bell")
                        .font(.subheadline)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func muteLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "暂停 \(minutes) 分钟"
        }
        return "暂停 \(minutes / 60) 小时"
    }

    private var countdownToggleRow: some View {
        HStack {
            Label("菜单栏显示剩余时间", systemImage: "clock.badge")
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $showCountdown)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text("菜单栏显示剩余时间"))
        }
    }

    private var launchAtLoginRow: some View {
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
    }

    private var pollingIntervalRow: some View {
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
    }

    @ViewBuilder
    private var launchAtLoginHints: some View {
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
    }

    private var resetStatisticsRow: some View {
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
