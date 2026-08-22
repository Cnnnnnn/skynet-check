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
    @Published public private(set) var sessionExpiryOutlived = false
    @Published public private(set) var sessionStatistics: SessionDurationStatistics?
    @Published public private(set) var loginURL: URL?
    @Published public private(set) var checkDurations = CheckDurationStats()
    @Published public private(set) var networkStability = NetworkStability()
    @Published public private(set) var skynetConfig: SkynetConfigSummary?
    @Published public private(set) var serviceTokens: [ServiceToken] = []
    @Published public private(set) var tokenValidation: [String: ServiceTokenValidationOutcome] = [:]
    @Published public private(set) var skillUpdatePhase: ComponentUpdatePhase = .idle
    @Published public private(set) var skillUpdateReport: SkillUpdateReport?
    @Published public private(set) var mcpVersionFindings: [McpVersionFinding] = []
    @Published public private(set) var skillUpdateFailureDetail: String?
    @Published public private(set) var componentUpdateCheckedAt: Date?

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
    private let configReader: SkynetConfigReader?
    private let skillUpdateChecker: (any SkillUpdateChecking)?
    private let mcpVersionChecker: (any McpVersionChecking)?
    private let componentUpdateStore: (any ComponentUpdateSnapshotStoring)?
    private var expiryTracker: SessionExpiryTracker
    private var expiryAdvisor = SessionExpiryAdvisor()
    private var periodicTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var refreshPending = false
    private var pendingResultNotification = false
    private var componentUpdateInProgress = false
    private var started = false
    private var notifiedInvalidTokenKeys: Set<String> = []

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

    public func login() async {
        guard !isChecking else {
            refreshPending = true
            return
        }

        isChecking = true
        state = .checking
        let loginResult = await checker.login(
            networkAvailable: networkMonitor.isAvailable,
            onLoginURL: { [weak self] url in
                // The URL is printed as soon as the login command starts;
                // show the manual-fallback button right away instead of
                // waiting for the whole (possibly stalled) flow.
                Task { @MainActor [weak self] in
                    self?.loginURL = url
                }
            }
        )
        let result = loginResult.state
        await complete(with: result)
        // Keep the login URL around when the flow did not finish; the
        // panel offers it as a manual fallback if no browser opened.
        loginURL = loginResult.loginURL
        MonitorLog.store.info(
            "login flow completed: \(result.presentation.title, privacy: .public)"
        )
        await handleTransition(result)
        await notifier.notifyLoginResult(loginResult)
        // A login unlocks the platform-backed skill check; re-run it right
        // away instead of leaving the panel on the needs-login hint.
        if result.isAuthenticated, skillUpdatePhase == .needsLogin {
            await checkComponentUpdates()
        }
    }

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

    public func inspectEnvironment() async {
        // Component-version checks hit the platform and npm registries and
        // can take seconds; they run beside the environment probes instead
        // of blocking them.
        if skillUpdateChecker != nil || mcpVersionChecker != nil {
            Task { await checkComponentUpdates() }
        }
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
            await notifyInvalidTokensIfNeeded()
        }
        if let configReader {
            skynetConfig = configReader.read()
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
        sessionExpiryOutlived = expiryTracker.hasOutlivedEstimate(now: date)
        sessionStatistics = expiryTracker.currentRecord.statistics

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

    // Compares locally installed skills/MCP packages against their remote
    // latest versions. Detection only — upgrades stay with the CLI.
    public func checkComponentUpdates() async {
        guard skillUpdateChecker != nil || mcpVersionChecker != nil else {
            return
        }
        guard !componentUpdateInProgress else {
            return
        }
        componentUpdateInProgress = true
        skillUpdatePhase = .checking

        async let skillResult = skillUpdateChecker?.checkForUpdates()
        async let mcpResult = mcpVersionChecker?.checkVersions()
        let (skills, mcps) = await (skillResult, mcpResult)

        if let skills {
            switch skills {
            case .needsLogin:
                skillUpdatePhase = .needsLogin
                skillUpdateReport = nil
                skillUpdateFailureDetail = nil
            case let .completed(report):
                skillUpdatePhase = .completed
                skillUpdateReport = report
                skillUpdateFailureDetail = nil
            case let .failed(reason):
                skillUpdatePhase = .failed
                skillUpdateReport = nil
                skillUpdateFailureDetail = reason
            }
            MonitorLog.store.info(
                "skill update check: \(skills.logLabel, privacy: .public)"
            )
        }
        if let mcps {
            mcpVersionFindings = mcps
            MonitorLog.store.info(
                "mcp version check: \(mcps.count, privacy: .public) server(s)"
            )
        }
        componentUpdateCheckedAt = now()
        await notifyComponentUpdatesIfNeeded()
        componentUpdateStore?.save(
            ComponentUpdateSnapshot(
                savedAt: componentUpdateCheckedAt!,
                skillPhase: skillUpdatePhase,
                skillReport: skillUpdateReport,
                mcpFindings: mcpVersionFindings
            )
        )
        componentUpdateInProgress = false
    }

    // One notification per "fell behind" episode; a fully clean completed
    // check re-arms it for the next drift.
    private var notifiedComponentUpdatesEpisode = false

    private func notifyComponentUpdatesIfNeeded() async {
        guard skillUpdatePhase == .completed else {
            return
        }
        let skillCount = skillUpdateReport?.updates.count ?? 0
        let mcpCount = mcpVersionFindings.filter(\.isUpgradable).count
        let hasUpdates = skillCount > 0 || mcpCount > 0
        if hasUpdates {
            guard !notifiedComponentUpdatesEpisode else {
                return
            }
            notifiedComponentUpdatesEpisode = true
            await notifier.notifyComponentUpdatesAvailable(
                skillCount: skillCount,
                mcpCount: mcpCount
            )
        } else {
            notifiedComponentUpdatesEpisode = false
        }
    }

    // Component versions drift on a daily cadence; piggyback on any
    // completed refresh (periodic, manual, wake, network recovery) but at
    // most once every two hours.
    private static let componentRecheckInterval: TimeInterval = 2 * 60 * 60

    private func maybeRecheckComponentUpdates() {
        guard skillUpdateChecker != nil || mcpVersionChecker != nil else {
            return
        }
        if let lastChecked = componentUpdateCheckedAt,
           now().timeIntervalSince(lastChecked) < Self.componentRecheckInterval
        {
            return
        }
        Task { await checkComponentUpdates() }
    }

    // The component card appears once a check has produced anything to say;
    // stores without checkers (tests) never show it.
    public var showsComponentUpdates: Bool {
        skillUpdateChecker != nil || mcpVersionChecker != nil
    }

    // No manifest URL configured means "检查更新" can only ever fail; the
    // panel hides the row instead.
    public var showsUpdateCheck: Bool {
        updateChecker != nil
    }

    public func diagnosticsReport() -> String {
        DiagnosticsComposer.compose(
            appVersion: currentAppVersion,
            state: state,
            lastCheckedAt: lastCheckedAt,
            lastCompletedState: lastCompletedState,
            sessionExpiresAt: sessionExpiresAt,
            sessionExpiryOutlived: sessionExpiryOutlived,
            pollingIntervalMinutes: pollingIntervalMinutes,
            notificationPermission: notificationPermission,
            permissionAudit: permissionAudit,
            environment: environmentReport,
            tokenValidation: tokenValidation,
            checkDurations: checkDurations,
            skynetConfig: skynetConfig,
            networkStability: networkStability,
            skillUpdatePhase: skillUpdatePhase,
            skillUpdateReport: skillUpdateReport,
            mcpVersionFindings: mcpVersionFindings
        )
    }

    public func resetSessionStatistics() {
        // Keep the current login period; only forget the observed durations
        // so a corrupted sample no longer skews the expiry estimate.
        expiryTracker = SessionExpiryTracker(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: expiryTracker.currentRecord.lastAuthenticatedAt
            )
        )
        sessionExpiryStore?.save(expiryTracker.currentRecord)
        sessionStatistics = nil
        sessionExpiresAt = expiryTracker.estimatedExpiry(now: now())
        sessionExpiryOutlived = expiryTracker.hasOutlivedEstimate(now: now())
        MonitorLog.store.info("session duration statistics reset")
    }

    // One notification per token per failure episode; a token that turns
    // valid again re-arms the alert.
    private func notifyInvalidTokensIfNeeded() async {
        let tokenByName = Dictionary(
            serviceTokens.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (key, outcome) in tokenValidation.sorted(by: { $0.key < $1.key }) {
            switch outcome {
            case .invalid:
                guard !notifiedInvalidTokenKeys.contains(key) else {
                    continue
                }
                notifiedInvalidTokenKeys.insert(key)
                await notifier.notifyServiceTokenInvalid(
                    key: key,
                    name: tokenByName[key]?.displayName ?? key
                )
            case .valid:
                notifiedInvalidTokenKeys.remove(key)
            case .unknown:
                break
            }
        }
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
