import XCTest
@testable import SkynetMonitorCore

@MainActor
final class MonitorStoreLifecycleTests: XCTestCase {
    func testCheckForUpdatesReportsNewerRelease() async {
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            updateChecker: StoreFakeUpdateChecker(
                manifest: AppUpdateManifest(
                    version: "0.3.0",
                    downloadURL: URL(string: "https://example.internal/m.dmg")!
                )
            ),
            currentAppVersion: "0.2.0"
        )

        await store.checkForUpdates()

        XCTAssertEqual(store.updateStatus, .available(version: "0.3.0"))
        XCTAssertEqual(store.availableUpdate?.version, "0.3.0")
    }

    func testCheckForUpdatesReportsUpToDate() async {
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            updateChecker: StoreFakeUpdateChecker(
                manifest: AppUpdateManifest(
                    version: "0.2.0",
                    downloadURL: URL(string: "https://example.internal/m.dmg")!
                )
            ),
            currentAppVersion: "0.2.0"
        )

        await store.checkForUpdates()

        XCTAssertEqual(
            store.updateStatus,
            .upToDate(currentVersion: "0.2.0")
        )
        XCTAssertNil(store.availableUpdate)
    }

    func testCheckForUpdatesReportsFailure() async {
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            updateChecker: StoreFakeUpdateChecker(error: URLError(.badURL)),
            currentAppVersion: "0.2.0"
        )

        await store.checkForUpdates()

        XCTAssertEqual(store.updateStatus, .failed)
        XCTAssertNil(store.availableUpdate)
    }

    func testLoginNotifiesWhenSessionIsAlreadyAuthenticated() async {
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [],
                loginResult: .alreadyAuthenticated(email: "user@example.com")
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil
        )

        await store.login()

        XCTAssertEqual(
            notifier.loginResults,
            [.alreadyAuthenticated(email: "user@example.com")]
        )
        XCTAssertEqual(store.state, .authenticated(email: "user@example.com"))
    }

    func testLoginNotifiesCompletedFailure() async {
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [],
                loginResult: .completed(.offline, loginURL: nil)
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: false),
            notifier: notifier,
            periodicInterval: nil
        )

        await store.login()

        XCTAssertEqual(notifier.loginResults, [.completed(.offline, loginURL: nil)])
        XCTAssertEqual(store.state, .offline)
    }
}
