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

        XCTAssertEqual(store.state, .authenticated(email: "user@example.com"))
        XCTAssertEqual(store.cliVersion, "2.7.29")
        XCTAssertNotNil(store.lastCheckedAt)
        XCTAssertEqual(network.startCount, 1)
        XCTAssertEqual(notifier.authorizationRequestCount, 1)
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
                loginResult: .completed(.offline)
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: false),
            notifier: notifier,
            periodicInterval: nil
        )

        await store.login()

        XCTAssertEqual(notifier.loginResults, [.completed(.offline)])
        XCTAssertEqual(store.state, .offline)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
    }
}

private actor StoreFakeChecker: SkynetAuthChecking {
    private var results: [LoginState]
    private let delay: Duration
    private let loginResult: LoginActionResult?
    private(set) var checkCount = 0

    init(
        results: [LoginState],
        delay: Duration = .zero,
        loginResult: LoginActionResult? = nil
    ) {
        self.results = results
        self.delay = delay
        self.loginResult = loginResult
    }

    func check(networkAvailable: Bool) async -> LoginState {
        checkCount += 1
        try? await Task.sleep(for: delay)
        return results.removeFirst()
    }

    func login(networkAvailable: Bool) async -> LoginActionResult {
        if let loginResult {
            return loginResult
        }
        return .completed(await check(networkAvailable: networkAvailable))
    }

    func version() async -> String? {
        "2.7.29"
    }
}

@MainActor
private final class StoreFakeNetworkMonitor: NetworkMonitoring {
    private(set) var startCount = 0
    var isAvailable: Bool

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) async {
        startCount += 1
    }

    func stop() {}
}

@MainActor
private final class StoreFakeNotifier: LoginNotifying {
    var permissionStatus: NotificationPermissionStatus = .authorized
    private(set) var authorizationRequestCount = 0
    private(set) var notificationCount = 0
    private(set) var manualCheckResults: [LoginState] = []
    private(set) var loginResults: [LoginActionResult] = []

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        permissionStatus
    }

    func notifyLoginExpired() async {
        notificationCount += 1
    }

    func notifyCheckResult(_ state: LoginState) async {
        manualCheckResults.append(state)
    }

    func notifyLoginResult(_ result: LoginActionResult) async {
        loginResults.append(result)
    }
}
