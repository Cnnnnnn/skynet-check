import AppKit
import Combine
import SkynetMonitorCore
import SwiftUI

@main
struct SkynetLoginMonitorApp: App {
    @StateObject private var store: MonitorStore
    private let launchAtLogin = LaunchAtLoginController()

    init() {
        let runner = ProcessCommandRunner()
        let locator = CLIPathLocator(runner: runner)
        let checker = SkynetAuthChecker(locator: locator, runner: runner)
        _store = StateObject(
            wrappedValue: MonitorStore(
                checker: checker,
                networkMonitor: NetworkMonitor(),
                notifier: LoginNotifier()
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: store,
                launchAtLogin: launchAtLogin
            )
        } label: {
            Label(
                store.state.presentation.title,
                systemImage: store.state.presentation.symbolName
            )
            .task {
                await store.start()
            }
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )
            ) { _ in
                store.handleWake()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
