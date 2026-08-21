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
        let notifier = LoginNotifier()
        let monitorStore = MonitorStore(
            checker: checker,
            networkMonitor: NetworkMonitor(),
            notifier: notifier,
            environmentDoctor: EnvironmentDoctor(
                locator: locator,
                checker: checker,
                runner: runner,
                cliVersionChecker: RegistryCLIVersionChecker()
            ),
            stateStore: LoginStateStore(),
            sessionExpiryStore: SessionExpiryStore(),
            serviceTokenReader: ServiceTokenStore(),
            tokenValidator: ConfluenceTokenValidator(),
            configReader: SkynetConfigReader(),
            skillUpdateChecker: SkillUpdateChecker(
                client: HTTPSkynetPlatformClient()
            ),
            mcpVersionChecker: McpVersionChecker(
                registry: HTTPNpmRegistryClient()
            ),
            updateChecker: AppConfiguration.updateManifestURL.map {
                HTTPAppUpdateChecker(manifestURL: $0)
            },
            currentAppVersion: Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        notifier.onAction = { [weak monitorStore] action in
            Task { @MainActor in
                switch action {
                case .login:
                    await monitorStore?.login()
                case .check:
                    await monitorStore?.refresh(notifyResult: true)
                }
            }
        }
        _store = StateObject(
            wrappedValue: monitorStore
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: store,
                launchAtLogin: launchAtLogin
            )
        } label: {
            Image(nsImage: MenuBarIcon.image(for: store.state))
                .accessibilityLabel(store.state.presentation.title)
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
