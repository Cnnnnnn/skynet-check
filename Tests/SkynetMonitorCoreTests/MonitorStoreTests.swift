import XCTest
@testable import SkynetMonitorCore

@MainActor
final class MonitorStoreTests: XCTestCase {
    func testStartRequestsNotificationsStartsNetworkAndChecksImmediately() async {
        let checker = StoreFakeChecker(
            results: [.authenticated(email: "user@example.com")]
        )
        let network = StoreFakeNetworkMonitor(isAvailable: true)
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: checker,
            networkMonitor: network,
            notifier: notifier,
            periodicInterval: nil
        )

        await store.start()
        let checkCount = await checker.checkCount
        await waitUntil { notifier.authorizationRequestCount == 1 }

        XCTAssertEqual(store.state, .authenticated(email: "user@example.com"))
        XCTAssertEqual(store.cliVersion, "2.7.29")
        XCTAssertNotNil(store.lastCheckedAt)
        XCTAssertEqual(network.startCount, 1)
        XCTAssertEqual(checkCount, 1)
    }

    func testStartPublishesNextAutomaticCheckTime() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.authenticated(email: nil)]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            now: { now }
        )

        await store.start()

        XCTAssertEqual(
            store.nextAutomaticCheckAt,
            Date(timeIntervalSince1970: 1_700_000_900)
        )
    }

    func testRefreshRetainsLastCompletedResultWhileAnotherCheckIsRunning() async {
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.authenticated(email: "user@example.com"), .offline],
                delay: .milliseconds(50)
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil
        )

        await store.refresh()
        let secondRefresh = Task { await store.refresh() }
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(
            store.lastCompletedState,
            .authenticated(email: "user@example.com")
        )

        await secondRefresh.value
    }

    func testOverlappingRefreshesCoalesceIntoOnePendingCheck() async {
        let checker = StoreFakeChecker(
            results: [
                .authenticated(email: nil),
                .authenticated(email: nil),
            ],
            delay: .milliseconds(50)
        )
        let store = MonitorStore(
            checker: checker,
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil
        )

        let first = Task { await store.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        let second = Task { await store.refresh() }
        await first.value
        await second.value
        let checkCount = await checker.checkCount

        XCTAssertEqual(checkCount, 2)
        XCTAssertFalse(store.isChecking)
    }

    func testConfirmedUnauthenticatedStateNotifiesOnce() async {
        let checker = StoreFakeChecker(
            results: [.unauthenticated, .unauthenticated, .unauthenticated]
        )
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: checker,
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil,
            confirmationDelay: .zero
        )

        await store.refresh()
        await waitUntil { notifier.notificationCount == 1 }
        await store.refresh()
        let checkCount = await checker.checkCount

        XCTAssertEqual(notifier.notificationCount, 1)
        XCTAssertEqual(checkCount, 3)
    }

    func testManualRefreshNotifiesWithCompletedCheckResult() async {
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.authenticated(email: "user@example.com")]
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil
        )

        await store.refresh(notifyResult: true)

        XCTAssertEqual(
            notifier.manualCheckResults,
            [.authenticated(email: "user@example.com")]
        )
    }

    func testAutomaticRefreshDoesNotNotifyCheckResult() async {
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.authenticated(email: "user@example.com")]
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil
        )

        await store.refresh()

        XCTAssertTrue(notifier.manualCheckResults.isEmpty)
    }

    func testPollingIntervalIsClampedAndPersistedWhenChanged() {
        let suiteName = "MonitorStorePollingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = PollingInterval(defaults: defaults)
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            pollingInterval: settings
        )

        store.setPollingInterval(90)

        XCTAssertEqual(store.pollingIntervalMinutes, 60)
        XCTAssertEqual(settings.minutes, 60)
    }

    func testInspectEnvironmentPublishesNotificationPermission() async {
        let notifier = StoreFakeNotifier()
        notifier.permissionStatus = .denied
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.authenticated(email: nil)]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil
        )

        await store.inspectEnvironment()

        XCTAssertEqual(store.notificationPermission, .denied)
    }

    func testRestoresLastCompletedSnapshotOnInit() {
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stateStore = StoreFakeStateStore()
        stateStore.snapshot = LoginStateSnapshot(
            state: .authenticated(email: "user@example.com"),
            completedAt: completedAt
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            stateStore: stateStore
        )

        XCTAssertEqual(store.state, .authenticated(email: "user@example.com"))
        XCTAssertEqual(store.lastCompletedState, .authenticated(email: "user@example.com"))
        XCTAssertEqual(store.lastCheckedAt, completedAt)
    }

    func testRefreshPersistsCompletedState() async {
        let stateStore = StoreFakeStateStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.unauthenticated]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            stateStore: stateStore,
            now: { now }
        )

        await store.refresh()

        XCTAssertEqual(stateStore.saved?.state, .unauthenticated)
        XCTAssertEqual(stateStore.saved?.completedAt, now)
    }

    func testPersistsServiceErrorWithoutCLIDetail() async {
        let stateStore = StoreFakeStateStore()
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.serviceError(message: "Error: secret registry url")]
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            stateStore: stateStore
        )

        await store.refresh()

        XCTAssertEqual(
            stateStore.saved?.state,
            .serviceError(message: "Skynet CLI reported an error")
        )
        XCTAssertEqual(
            store.lastCompletedState,
            .serviceError(message: "Error: secret registry url")
        )
    }

    func testTwoManualUnauthenticatedChecksConfirmExpiryNotification() async {
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.unauthenticated, .unauthenticated]
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil,
            confirmationDelay: .seconds(300)
        )

        await store.refresh(notifyResult: true)
        await store.refresh(notifyResult: true)

        // Manual checks advance the confirmation counter just like the
        // scheduled 30-second recheck; see LoginTransitionTracker.
        XCTAssertEqual(notifier.notificationCount, 1)
    }

    func testWakeDefersRefreshUntilNetworkSettles() async {
        let checker = StoreFakeChecker(results: [.authenticated(email: nil)])
        let store = MonitorStore(
            checker: checker,
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            wakeDelay: .seconds(30)
        )

        store.handleWake()
        try? await Task.sleep(for: .milliseconds(100))
        let checkCount = await checker.checkCount

        XCTAssertEqual(checkCount, 0)
    }

    func testWakeRefreshesAfterDelay() async {
        let checker = StoreFakeChecker(results: [.authenticated(email: nil)])
        let store = MonitorStore(
            checker: checker,
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            wakeDelay: .zero
        )

        store.handleWake()
        await waitUntil { store.lastCheckedAt != nil }
        let checkCount = await checker.checkCount

        XCTAssertEqual(checkCount, 1)
        XCTAssertEqual(store.state, .authenticated(email: nil))
    }

}
