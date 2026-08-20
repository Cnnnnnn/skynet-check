import Combine
import Foundation

@MainActor
public final class MonitorStore: ObservableObject {
    @Published public private(set) var state: LoginState = .checking
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var lastCompletedState: LoginState?
    @Published public private(set) var nextAutomaticCheckAt: Date?
    @Published public private(set) var cliVersion: String?
    @Published public private(set) var isChecking = false
    @Published public private(set) var pollingIntervalMinutes: Int
    @Published public private(set) var environmentReport: EnvironmentReport?
    @Published public private(set) var notificationPermission: NotificationPermissionStatus = .unsupported
    @Published public private(set) var permissionAudit: SkynetPermissionAudit
    @Published public private(set) var permissionRepairMessage: String?
    @Published public private(set) var updateStatus: AppUpdateStatus = .idle
    @Published public private(set) var availableUpdate: AppUpdateManifest?
    @Published public private(set) var sessionExpiresAt: Date?
    @Published public private(set) var serviceTokens: [ServiceToken] = []
    @Published public private(set) var tokenValidation: [String: ServiceTokenValidationOutcome] = [:]

    private let checker: any SkynetAuthChecking
    private let networkMonitor: any NetworkMonitoring
    private let notifier: any LoginNotifying
    private let periodicChecksEnabled: Bool
    private let pollingInterval: PollingInterval
    private let environmentDoctor: EnvironmentDoctor?
    private let permissionManager: SkynetPermissionManager
    private let updateChecker: (any AppUpdateChecking)?
    private let currentAppVersion: String?
    private let confirmationDelay: Duration
    private let wakeDelay: Duration
    private let now: @Sendable () -> Date

    private var transitionTracker = LoginTransitionTracker()
    private let stateStore: (any LoginStateStoring)?
    private let sessionExpiryStore: (any SessionExpiryStoring)?
    private let serviceTokenReader: (any ServiceTokenReading)?
    private let tokenValidator: (any ServiceTokenValidating)?
    private var expiryTracker: SessionExpiryTracker
    private var expiryAdvisor = SessionExpiryAdvisor()
    private var periodicTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var refreshPending = false
    private var pendingResultNotification = false
    private var started = false

    public init(
        checker: any SkynetAuthChecking,
        networkMonitor: any NetworkMonitoring,
        notifier: any LoginNotifying,
        periodicInterval: Duration? = .seconds(15 * 60),
        confirmationDelay: Duration = .seconds(30),
        wakeDelay: Duration = .seconds(3),
        pollingInterval: PollingInterval = PollingInterval(),
        environmentDoctor: EnvironmentDoctor? = nil,
        permissionManager: SkynetPermissionManager = SkynetPermissionManager(),
        stateStore: (any LoginStateStoring)? = nil,
        sessionExpiryStore: (any SessionExpiryStoring)? = nil,
        serviceTokenReader: (any ServiceTokenReading)? = nil,
        tokenValidator: (any ServiceTokenValidating)? = nil,
        updateChecker: (any AppUpdateChecking)? = nil,
        currentAppVersion: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.checker = checker
        self.networkMonitor = networkMonitor
        self.notifier = notifier
        self.periodicChecksEnabled = periodicInterval != nil
        self.confirmationDelay = confirmationDelay
        self.wakeDelay = wakeDelay
        self.pollingInterval = pollingInterval
        self.pollingIntervalMinutes = pollingInterval.minutes
        self.environmentDoctor = environmentDoctor
        self.permissionManager = permissionManager
        self.stateStore = stateStore
        self.sessionExpiryStore = sessionExpiryStore
        self.serviceTokenReader = serviceTokenReader
        self.tokenValidator = tokenValidator
        self.expiryTracker = SessionExpiryTracker(
            record: sessionExpiryStore?.load() ?? SessionExpiryRecord()
        )
        self.updateChecker = updateChecker
        self.currentAppVersion = currentAppVersion
        self.now = now
        self.permissionAudit = permissionManager.audit()

        // Show the last known outcome immediately on launch; the first
        // refresh in start() replaces it with a fresh result.
        if let snapshot = stateStore?.load() {
            state = snapshot.state
            lastCompletedState = snapshot.state
            lastCheckedAt = snapshot.completedAt
            MonitorLog.store.info("restored last completed check from snapshot")
        }
        if let estimatedExpiry = expiryTracker.estimatedExpiry(now: now()) {
            sessionExpiresAt = estimatedExpiry
        }
    }

    public func start() async {
        guard !started else {
            return
        }
        started = true

        await notifier.requestAuthorization()
        await networkMonitor.start { [weak self] available in
            self?.handleNetworkChange(available: available)
        }

        // The first check decides the menu bar state and must not wait for
        // the slow environment probes; version and diagnostics run in
        // parallel and settle before start() returns.
        async let version = checker.version()
        async let inspection = inspectEnvironment()
        await refresh()
        cliVersion = await version
        await inspection
        startPeriodicChecks()
        MonitorLog.store.info("monitor started")
    }

    public func refresh(notifyResult: Bool = false) async {
        if isChecking {
            refreshPending = true
            pendingResultNotification = pendingResultNotification || notifyResult
            return
        }

        var notifyCurrentResult = notifyResult
        repeat {
            refreshPending = false
            isChecking = true
            state = .checking

            let result = await checker.check(
                networkAvailable: networkMonitor.isAvailable
            )

            await complete(with: result)
            MonitorLog.store.info(
                "check completed: \(result.presentation.title, privacy: .public)"
            )
            await handleTransition(result)
            if notifyCurrentResult {
                await notifier.notifyCheckResult(result)
            }
            notifyCurrentResult = pendingResultNotification
            pendingResultNotification = false
        } while refreshPending
    }

    public func login() async {
        guard !isChecking else {
            refreshPending = true
            return
        }

        isChecking = true
        state = .checking
        let loginResult = await checker.login(
            networkAvailable: networkMonitor.isAvailable
        )
        let result = loginResult.state
        await complete(with: result)
        MonitorLog.store.info(
            "login flow completed: \(result.presentation.title, privacy: .public)"
        )
        await handleTransition(result)
        await notifier.notifyLoginResult(loginResult)
    }

    public func handleWake() {
        MonitorLog.store.info("system woke; scheduling refresh")
        // Networking (Wi-Fi reassociation, VPN) needs a moment after wake;
        // checking immediately misreports "offline" until the path settles.
        // Repeated wake notifications coalesce into a single deferred check.
        wakeTask?.cancel()
        let delay = wakeDelay
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            await self?.refresh()
        }
    }

    public func stop() {
        periodicTask?.cancel()
        confirmationTask?.cancel()
        wakeTask?.cancel()
        periodicTask = nil
        confirmationTask = nil
        wakeTask = nil
        nextAutomaticCheckAt = nil
        networkMonitor.stop()
        started = false
        MonitorLog.store.info("monitor stopped")
    }

    public func setPollingInterval(_ minutes: Int) {
        let clamped = PollingInterval.clamped(minutes)
        pollingInterval.setMinutes(clamped)
        pollingIntervalMinutes = clamped
        MonitorLog.store.info(
            "polling interval set to \(clamped, privacy: .public) minutes"
        )

        guard started, periodicChecksEnabled else {
            return
        }
        periodicTask?.cancel()
        periodicTask = nil
        startPeriodicChecks()
    }

    public func inspectEnvironment() async {
        notificationPermission = await notifier.authorizationStatus()
        if let serviceTokenReader {
            // Values are published for the panel's copy action only; never
            // logged and never part of the diagnostics report.
            let tokens = serviceTokenReader.availableTokens()
            serviceTokens = tokens
            MonitorLog.store.info(
                "loaded \(tokens.count, privacy: .public) service token(s)"
            )
            tokenValidation = await validateTokens(tokens)
        }
        guard let environmentDoctor else {
            return
        }
        environmentReport = await environmentDoctor.inspect(
            networkAvailable: networkMonitor.isAvailable
        )
        permissionAudit = permissionManager.audit()
    }

    public func repairPermissions() {
        do {
            try permissionManager.repair()
            permissionAudit = permissionManager.audit()
            permissionRepairMessage = MonitorText.Permission.repaired
        } catch {
            permissionRepairMessage = MonitorText.Permission.repairFailed
        }
    }

    public func checkForUpdates() async {
        guard let updateChecker else {
            return
        }
        updateStatus = .checking
        do {
            let manifest = try await updateChecker.latestRelease()
            let status = AppUpdateEvaluator.evaluate(
                currentVersion: currentAppVersion ?? "",
                manifest: manifest
            )
            updateStatus = status
            if case .available = status {
                availableUpdate = manifest
            } else {
                availableUpdate = nil
            }
            MonitorLog.store.info(
                "update check finished: \(status.logLabel, privacy: .public)"
            )
        } catch {
            updateStatus = .failed
            availableUpdate = nil
            MonitorLog.store.error(
                "update check failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func complete(with result: LoginState) async {
        let completedAt = now()
        state = result
        lastCompletedState = result
        lastCheckedAt = completedAt
        isChecking = false
        stateStore?.save(
            LoginStateSnapshot(
                state: result.persistenceSafe,
                completedAt: completedAt
            )
        )
        await handleSessionExpiry(result, at: completedAt)
    }

    private func handleSessionExpiry(_ result: LoginState, at date: Date) async {
        expiryTracker.recordState(result, at: date)
        sessionExpiryStore?.save(expiryTracker.currentRecord)

        let estimatedExpiry = expiryTracker.estimatedExpiry(now: date)
        sessionExpiresAt = estimatedExpiry

        let sessionStartedAt = expiryTracker.currentRecord.lastAuthenticatedAt
        if let stage = expiryAdvisor.evaluate(
            estimatedExpiry: estimatedExpiry,
            sessionStartedAt: sessionStartedAt,
            now: date
        ), let estimatedExpiry {
            MonitorLog.store.notice(
                "session expiry estimate crossed a threshold (\(stage.logLabel, privacy: .public))"
            )
            await notifier.notifySessionExpiring(
                stage: stage,
                expiresAt: estimatedExpiry
            )
        }
    }

    public func diagnosticsReport() -> String {
        DiagnosticsComposer.compose(
            appVersion: currentAppVersion,
            state: state,
            lastCheckedAt: lastCheckedAt,
            lastCompletedState: lastCompletedState,
            sessionExpiresAt: sessionExpiresAt,
            pollingIntervalMinutes: pollingIntervalMinutes,
            notificationPermission: notificationPermission,
            permissionAudit: permissionAudit,
            environment: environmentReport,
            tokenValidation: tokenValidation
        )
    }

    private func validateTokens(
        _ tokens: [ServiceToken]
    ) async -> [String: ServiceTokenValidationOutcome] {
        guard let tokenValidator else {
            return [:]
        }

        // Outcomes carry no token material — only the per-key verdict.
        return await withTaskGroup(
            of: (String, ServiceTokenValidationOutcome).self
        ) { group in
            for token in tokens where tokenValidator.supportedKeys.contains(token.key) {
                group.addTask {
                    let outcome = await tokenValidator.validate(token: token)
                    MonitorLog.store.info(
                        "token \(token.key, privacy: .public) validation: \(outcome.logLabel, privacy: .public)"
                    )
                    return (token.key, outcome)
                }
            }
            var results: [String: ServiceTokenValidationOutcome] = [:]
            for await (key, outcome) in group {
                results[key] = outcome
            }
            return results
        }
    }

    private func handleTransition(_ result: LoginState) async {
        switch transitionTracker.consume(result) {
        case .none:
            if result != .unauthenticated {
                confirmationTask?.cancel()
                confirmationTask = nil
            }

        case .confirmAfter:
            confirmationTask?.cancel()
            let delay = confirmationDelay
            confirmationTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else {
                    return
                }
                await self?.refresh()
            }

        case .notifyExpired:
            confirmationTask = nil
            MonitorLog.store.notice("login expiry confirmed; notifying user")
            await notifier.notifyLoginExpired()
        }
    }

    private func handleNetworkChange(available: Bool) {
        MonitorLog.store.info(
            "network became \(available ? "available" : "unavailable", privacy: .public)"
        )
        if available {
            Task { [weak self] in
                await self?.refresh()
            }
        } else if !isChecking {
            state = .offline
        }
    }

    private func startPeriodicChecks() {
        guard periodicTask == nil, periodicChecksEnabled else {
            return
        }
        let periodicInterval = Duration.seconds(pollingIntervalMinutes * 60)
        nextAutomaticCheckAt = now().addingTimeInterval(
            TimeInterval(pollingIntervalMinutes * 60)
        )

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: periodicInterval)
                guard !Task.isCancelled else {
                    return
                }
                await self?.refresh()
                self?.nextAutomaticCheckAt = self?.now().addingTimeInterval(
                    TimeInterval(self?.pollingIntervalMinutes ?? 0) * 60
                )
            }
        }
    }
}
