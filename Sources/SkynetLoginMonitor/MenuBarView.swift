import AppKit
import SkynetMonitorCore
import SwiftUI

@MainActor
struct MenuBarView: View {
    @ObservedObject private var store: MonitorStore
    private let launchAtLogin: any LaunchAtLoginControlling

    @State private var launchAtLoginEnabled: Bool
    @State private var launchAtLoginMessage: String?
    @State private var installCommandCopied = false

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

            if let email = store.state.authenticatedEmail {
                Label(email, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                if let cliVersion = store.cliVersion {
                    Label("CLI \(cliVersion)", systemImage: "terminal")
                }
                if let lastCheckedAt = store.lastCheckedAt {
                    Label(
                        lastCheckedAt.formatted(date: .omitted, time: .shortened),
                        systemImage: "clock"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            if store.state == .cliMissing {
                missingCLICard
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await store.refresh(notifyResult: true) }
                    } label: {
                        Label("立即检查", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isChecking)

                    Button {
                        Task { await store.login() }
                    } label: {
                        Label("重新登录", systemImage: "person.crop.circle.badge.arrow.right")
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

            Divider()

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
            }

            HStack(spacing: 10) {
                Label("自动检查", systemImage: "timer")
                    .font(.subheadline)
                Slider(
                    value: pollingIntervalBinding,
                    in: 3.0...60.0,
                    step: 1
                )
                Text("\(store.pollingIntervalMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

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
                Text("Skynet Login Monitor")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
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

    private var missingCLICard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要先安装 Skynet CLI", systemImage: "shippingbox")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("复制命令后粘贴到 Terminal 执行，完成后回来重新检测。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CLIInstallGuide.combinedCommand)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 8) {
                Button("复制命令") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        CLIInstallGuide.combinedCommand,
                        forType: .string
                    )
                    installCommandCopied = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("打开 Terminal") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        CLIInstallGuide.combinedCommand,
                        forType: .string
                    )
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("重新检测") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(store.isChecking)
            }

            if installCommandCopied {
                Text("安装命令已复制")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
