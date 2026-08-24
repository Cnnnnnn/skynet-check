import AppKit
import Combine
import SkynetMonitorCore
import SwiftUI

@main
struct SkynetLoginMonitorApp: App {
    @StateObject private var store: MonitorStore
    private let launchAtLogin = LaunchAtLoginController()
    private let muteStore = NotificationMuteStore()
    @AppStorage("menuBarShowsCountdown") private var showCountdown = false
    // Ticking once a minute keeps the countdown fresh without a busy loop.
    @State private var now = Date()
    private let tickTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        let runner = ProcessCommandRunner()
        let locator = CLIPathLocator(runner: runner)
        let checker = SkynetAuthChecker(locator: locator, runner: runner)
        let muteStore = NotificationMuteStore()
        let notifier = LoginNotifier(
            // The notifier reads the same persisted window the settings
            // row writes; while active every notification is dropped.
            muteProvider: { muteStore.load() }
        )
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
            componentUpdateStore: ComponentUpdateSnapshotStore(),
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
                launchAtLogin: launchAtLogin,
                muteStore: muteStore
            )
        } label: {
            MenuBarLabel(
                state: store.state,
                sessionExpiresAt: store.sessionExpiresAt,
                showCountdown: showCountdown,
                now: now
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
            .onReceive(tickTimer) { date in
                now = date
            }
        }
        .menuBarExtraStyle(.window)
    }
}
