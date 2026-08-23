import Combine
import Foundation

@MainActor
public final class MonitorStore: ObservableObject {
    // Setters for state/isChecking are internal: the login and refresh
    // flows in the extension files publish through them.
    @Published public internal(set) var state: LoginState = .checking
    @Published public internal(set) var isChecking = false
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var lastCompletedState: LoginState?
    @Published public private(set) var nextAutomaticCheckAt: Date?
    @Published public private(set) var cliVersion: String?
    @Published public private(set) var pollingIntervalMinutes: Int
    @Published public internal(set) var environmentReport: EnvironmentReport?
    @Published public internal(set) var notificationPermission: NotificationPermissionStatus = .unsupported
    @Published public internal(set) var permissionAudit: SkynetPermissionAudit
    @Published public internal(set) var permissionRepairMessage: String?
    // Setter is internal so MonitorStore+AppUpdates.swift can publish
    // results from its own file.
    @Published public internal(set) var updateStatus: AppUpdateStatus = .idle
    @Published public internal(set) var availableUpdate: AppUpdateManifest?
    // Setters are internal (not private) so MonitorStore+SessionExpiry.swift
    // can publish results from its own file.
    @Published public internal(set) var sessionExpiresAt: Date?
    @Published public internal(set) var sessionExpiryOutlived = false
    @Published public internal(set) var sessionStatistics: SessionDurationStatistics?
    @Published public internal(set) var loginURL: URL?
    @Published public private(set) var checkDurations = CheckDurationStats()
    @Published public private(set) var networkStability = NetworkStability()
    @Published public internal(set) var skynetConfig: SkynetConfigSummary?
    @Published public internal(set) var serviceTokens: [ServiceToken] = []
    @Published public internal(set) var tokenValidation: [String: ServiceTokenValidationOutcome] = [:]
    // Setters are internal (not private) so MonitorStore+ComponentUpdates.swift
    // can publish results from its own file.
    @Published public internal(set) var skillUpdatePhase: ComponentUpdatePhase = .idle
    @Published public internal(set) var skillUpdateReport: SkillUpdateReport?
    @Published public internal(set) var mcpVersionFindings: [McpVersionFinding] = []
    @Published public internal(set) var skillUpdateFailureDetail: String?
    @Published public internal(set) var componentUpdateCheckedAt: Date?

    // Access level note: these are `let var` internal (not private) because
    // MonitorStore+ComponentUpdates.swift extends the class in another file.
    let checker: any SkynetAuthChecking
    let networkMonitor: any NetworkMonitoring
    let notifier: any LoginNotifying
    private let periodicChecksEnabled: Bool
    private let pollingInterval: PollingInterval
    let environmentDoctor: EnvironmentDoctor?
    let permissionManager: SkynetPermissionManager
    let updateChecker: (any AppUpdateChecking)?
    let currentAppVersion: String?
    private let confirmationDelay: Duration
    private let wakeDelay: Duration
    let now: @Sendable () -> Date

    private var transitionTracker = LoginTransitionTracker()
    private let stateStore: (any LoginStateStoring)?
    let sessionExpiryStore: (any SessionExpiryStoring)?
    let serviceTokenReader: (any ServiceTokenReading)?
    let tokenValidator: (any ServiceTokenValidating)?
    let configReader: SkynetConfigReader?
    let skillUpdateChecker: (any SkillUpdateChecking)?
    let mcpVersionChecker: (any McpVersionChecking)?
    let componentUpdateStore: (any ComponentUpdateSnapshotStoring)?
    var expiryTracker: SessionExpiryTracker
    var expiryAdvisor = SessionExpiryAdvisor()
    private var periodicTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    var refreshPending = false
    private var pendingResultNotification = false
    var componentUpdateInProgress = false
    // One notification per "fell behind" episode; see
    // MonitorStore+ComponentUpdates.swift.
    var notifiedComponentUpdatesEpisode = false
    private var started = false
    var notifiedInvalidTokenKeys: Set<String> = []

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
        configReader: SkynetConfigReader? = nil,
        skillUpdateChecker: (any SkillUpdateChecking)? = nil,
        mcpVersionChecker: (any McpVersionChecking)? = nil,
        componentUpdateStore: (any ComponentUpdateSnapshotStoring)? = nil,
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
        self.configReader = configReader
        self.skillUpdateChecker = skillUpdateChecker
        self.mcpVersionChecker = mcpVersionChecker
        self.componentUpdateStore = componentUpdateStore
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
        sessionExpiryOutlived = expiryTracker.hasOutlivedEstimate(now: now())
        sessionStatistics = expiryTracker.currentRecord.statistics

        // Show the last component-version result immediately; the check
        // fired by start()'s inspectEnvironment replaces it with fresh data.
        if let snapshot = componentUpdateStore?.load() {
            skillUpdatePhase = snapshot.skillPhase
            skillUpdateReport = snapshot.skillReport
            mcpVersionFindings = snapshot.mcpFindings
            componentUpdateCheckedAt = snapshot.savedAt
            MonitorLog.store.info(
                "restored last component-version check from snapshot"
            )
        }
    }

    public func start() async {
        guard !started else {
            return
        }
        started = true

        // Authorization shows a system prompt that blocks until the user
        // answers; keep it off the critical path so the first check and
        // network monitoring never wait behind the dialog.
        Task { [notifier] in
            await notifier.requestAuthorization()
        }

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

            let checkStartedAt = Date()
            let result = await checker.check(
                networkAvailable: networkMonitor.isAvailable
            )
            checkDurations.record(
                Date().timeIntervalSince(checkStartedAt)
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
        maybeRecheckComponentUpdates()
    }

    // The interactive login flow lives in MonitorStore+Login.swift.

    public func handleWake() {
        MonitorLog.store.info("system woke; scheduling refresh")
        // Reset the periodic timer: after a long sleep its deadline has
        // already passed and would fire immediately on wake, duplicating
        // the deferred refresh below.
        if started, periodicChecksEnabled {
            periodicTask?.cancel()
            periodicTask = nil
            startPeriodicChecks()
        }
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

    // Environment inspection and permission repair live in
    // MonitorStore+Environment.swift.

    // App self-update check and diagnostics report live in
    // MonitorStore+AppUpdates.swift.

    func complete(with result: LoginState) async {
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

    // Session-expiry estimation, statistics and notifications live in
    // MonitorStore+SessionExpiry.swift.

    // Service-token validation and alerting live in
    // MonitorStore+TokenValidation.swift.

    func handleTransition(_ result: LoginState) async {
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
        let timestamp = now()
        if available {
            networkStability.recordRecovery(at: timestamp)
            Task { [weak self] in
                await self?.refresh()
            }
        } else {
            networkStability.recordOutage(at: timestamp)
            if !isChecking {
                state = .offline
            }
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
