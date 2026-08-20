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
    private(set) var checkCount = 0

    init(results: [LoginState], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func check(networkAvailable: Bool) async -> LoginState {
        checkCount += 1
        try? await Task.sleep(for: delay)
        return results.removeFirst()
    }

    func login(networkAvailable: Bool) async -> LoginState {
        await check(networkAvailable: networkAvailable)
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

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        startCount += 1
    }

    func stop() {}
}

@MainActor
private final class StoreFakeNotifier: LoginNotifying {
    private(set) var authorizationRequestCount = 0
    private(set) var notificationCount = 0

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func notifyLoginExpired() async {
        notificationCount += 1
    }
}
