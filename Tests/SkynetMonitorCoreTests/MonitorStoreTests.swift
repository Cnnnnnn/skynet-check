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

    func testRefreshNotifiesOnceWhenEstimatedExpiryApproaches() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let notifier = StoreFakeNotifier()
        // Past sessions lasted 2h; the current one started 90 minutes ago,
        // so the estimate sits 30 minutes out — inside the warning window.
        let expiryStore = StoreFakeSessionExpiryStore(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: now.addingTimeInterval(-5400),
                durations: [7200]
            )
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.authenticated(email: nil), .authenticated(email: nil)]
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil,
            sessionExpiryStore: expiryStore,
            now: { now }
        )

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(notifier.expiringNotifications.count, 1)
        XCTAssertEqual(notifier.expiringNotifications.first?.stage, .warning)
        XCTAssertEqual(
            store.sessionExpiresAt,
            now.addingTimeInterval(1800)
        )
    }

    func testRefreshMarksOutlivedEstimateWhenPastHistoricalShortest() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.authenticated(email: nil)]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: StoreFakeSessionExpiryStore(
                record: SessionExpiryRecord(
                    lastAuthenticatedAt: now.addingTimeInterval(-5000),
                    durations: [3600]
                )
            ),
            now: { now }
        )

        await store.refresh()

        XCTAssertNil(store.sessionExpiresAt)
        XCTAssertTrue(store.sessionExpiryOutlived)
    }

    func testRefreshCapturesSessionDurationWhenExpiryDetected() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiryStore = StoreFakeSessionExpiryStore(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: now.addingTimeInterval(-3600),
                durations: []
            )
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.unauthenticated]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: expiryStore,
            now: { now }
        )

        await store.refresh()

        XCTAssertEqual(expiryStore.saved?.durations, [3600])
        XCTAssertNil(store.sessionExpiresAt)
    }

    func testStatisticsPublishFromPersistedRecordOnInit() {
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: StoreFakeSessionExpiryStore(
                record: SessionExpiryRecord(durations: [3600, 7200])
            )
        )

        XCTAssertEqual(store.sessionStatistics?.observationCount, 2)
        XCTAssertEqual(store.sessionStatistics?.average ?? 0, 5400, accuracy: 1)
    }

    func testResetSessionStatisticsClearsDurationsButKeepsCurrentSession() {
        let expiryStore = StoreFakeSessionExpiryStore(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                durations: [3600, 7200]
            )
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: expiryStore
        )

        store.resetSessionStatistics()

        XCTAssertNil(store.sessionStatistics)
        XCTAssertNil(store.sessionExpiresAt)
        XCTAssertEqual(
            expiryStore.saved?.lastAuthenticatedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(expiryStore.saved?.durations, [])
    }

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

private final class StoreFakeSessionExpiryStore: SessionExpiryStoring, @unchecked Sendable {
    var record: SessionExpiryRecord?
    private(set) var saved: SessionExpiryRecord?

    init(record: SessionExpiryRecord? = nil) {
        self.record = record
    }

    func load() -> SessionExpiryRecord? {
        record
    }

    func save(_ record: SessionExpiryRecord) {
        self.record = record
        saved = record
    }
}

private struct StoreFakeUpdateChecker: AppUpdateChecking {
    private let manifest: AppUpdateManifest?
    private let error: Error?

    init(manifest: AppUpdateManifest) {
        self.manifest = manifest
        self.error = nil
    }

    init(error: Error) {
        self.manifest = nil
        self.error = error
    }

    func latestRelease() async throws -> AppUpdateManifest {
        if let error {
            throw error
        }
        return manifest!
    }
}

private final class StoreFakeStateStore: LoginStateStoring, @unchecked Sendable {
    var snapshot: LoginStateSnapshot?
    private(set) var saved: LoginStateSnapshot?

    func load() -> LoginStateSnapshot? {
        snapshot
    }

    func save(_ snapshot: LoginStateSnapshot) {
        saved = snapshot
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
        return LoginActionResult(state: await check(networkAvailable: networkAvailable))
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
    private(set) var expiringNotifications: [(stage: SessionExpiryAdvisor.Stage, expiresAt: Date)] = []
    private(set) var invalidTokenNotifications: [(key: String, name: String)] = []

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        permissionStatus
    }

    func notifyLoginExpired() async {
        notificationCount += 1
    }

    func notifyServiceTokenInvalid(key: String, name: String) async {
        invalidTokenNotifications.append((key, name))
    }

    func notifySessionExpiring(
        stage: SessionExpiryAdvisor.Stage,
        expiresAt: Date
    ) async {
        expiringNotifications.append((stage, expiresAt))
    }

    func notifyCheckResult(_ state: LoginState) async {
        manualCheckResults.append(state)
    }

    func notifyLoginResult(_ result: LoginActionResult) async {
        loginResults.append(result)
    }
}
