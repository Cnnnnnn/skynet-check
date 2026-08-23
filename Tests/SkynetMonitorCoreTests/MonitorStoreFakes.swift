import XCTest
@testable import SkynetMonitorCore

// Shared fakes for the MonitorStore test classes. Intentionally internal so
// several test files can use them.

@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        await Task.yield()
    }
}

final class StoreFakeSessionExpiryStore: SessionExpiryStoring, @unchecked Sendable {
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

struct StoreFakeUpdateChecker: AppUpdateChecking {
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

final class StoreFakeStateStore: LoginStateStoring, @unchecked Sendable {
    var snapshot: LoginStateSnapshot?
    private(set) var saved: LoginStateSnapshot?

    func load() -> LoginStateSnapshot? {
        snapshot
    }

    func save(_ snapshot: LoginStateSnapshot) {
        saved = snapshot
    }
}

actor StoreFakeChecker: SkynetAuthChecking {
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
final class StoreFakeNetworkMonitor: NetworkMonitoring {
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
final class StoreFakeNotifier: LoginNotifying {
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
