import AppKit
import SkynetMonitorCore
import SwiftUI

@MainActor
struct MenuBarView: View {
    @ObservedObject private var store: MonitorStore
    private let launchAtLogin: any LaunchAtLoginControlling

    @State private var launchAtLoginEnabled: Bool
    @State private var launchAtLoginMessage: String?

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

        Label(presentation.title, systemImage: presentation.symbolName)
            .foregroundStyle(presentation.tint.color)

        if let email = store.state.authenticatedEmail {
            Text(email)
        }
        if let cliVersion = store.cliVersion {
            Text("Skynet CLI \(cliVersion)")
        }
        if let lastCheckedAt = store.lastCheckedAt {
            Text("上次检查：\(lastCheckedAt.formatted(date: .omitted, time: .shortened))")
        }
        if case let .serviceError(message) = store.state {
            Text(message)
        }

        Divider()

        Button("立即检查") {
            Task {
                await store.refresh(notifyResult: true)
            }
        }
        .disabled(store.isChecking)

        Button("重新登录") {
            Task {
                await store.login()
            }
        }
        .disabled(store.isChecking || store.state == .cliMissing)

        Toggle(
            "开机启动",
            isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { enabled in
                    setLaunchAtLogin(enabled)
                }
            )
        )

        if launchAtLogin.requiresApproval {
            Text("需要在“系统设置 → 登录项”中允许")
        }
        if let launchAtLoginMessage {
            Text(launchAtLoginMessage)
        }

        Divider()

        Button("退出") {
            store.stop()
            NSApplication.shared.terminate(nil)
        }
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
