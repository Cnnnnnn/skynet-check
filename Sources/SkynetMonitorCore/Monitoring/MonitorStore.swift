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

    private let checker: any SkynetAuthChecking
    private let networkMonitor: any NetworkMonitoring
    private let notifier: any LoginNotifying
    private let periodicChecksEnabled: Bool
    private let pollingInterval: PollingInterval
    private let environmentDoctor: EnvironmentDoctor?
    private let permissionManager: SkynetPermissionManager
    private let confirmationDelay: Duration
    private let now: @Sendable () -> Date

    private var transitionTracker = LoginTransitionTracker()
    private var periodicTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var refreshPending = false
    private var pendingResultNotification = false
    private var started = false

    public init(
        checker: any SkynetAuthChecking,
        networkMonitor: any NetworkMonitoring,
        notifier: any LoginNotifying,
        periodicInterval: Duration? = .seconds(15 * 60),
        confirmationDelay: Duration = .seconds(30),
        pollingInterval: PollingInterval = PollingInterval(),
        environmentDoctor: EnvironmentDoctor? = nil,
        permissionManager: SkynetPermissionManager = SkynetPermissionManager(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.checker = checker
        self.networkMonitor = networkMonitor
        self.notifier = notifier
        self.periodicChecksEnabled = periodicInterval != nil
        self.confirmationDelay = confirmationDelay
        self.pollingInterval = pollingInterval
        self.pollingIntervalMinutes = pollingInterval.minutes
        self.environmentDoctor = environmentDoctor
        self.permissionManager = permissionManager
        self.now = now
        self.permissionAudit = permissionManager.audit()
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

        cliVersion = await checker.version()
        await inspectEnvironment()
        await refresh()
        startPeriodicChecks()
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

            state = result
            lastCompletedState = result
            lastCheckedAt = Date()
            isChecking = false
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
        state = result
        lastCompletedState = result
        lastCheckedAt = Date()
        isChecking = false
        await handleTransition(result)
        await notifier.notifyLoginResult(loginResult)
    }

    public func handleWake() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    public func stop() {
        periodicTask?.cancel()
        confirmationTask?.cancel()
        periodicTask = nil
        confirmationTask = nil
        nextAutomaticCheckAt = nil
        networkMonitor.stop()
        started = false
    }

    public func setPollingInterval(_ minutes: Int) {
        let clamped = PollingInterval.clamped(minutes)
        pollingInterval.setMinutes(clamped)
        pollingIntervalMinutes = clamped

        guard started, periodicChecksEnabled else {
            return
        }
        periodicTask?.cancel()
        periodicTask = nil
        startPeriodicChecks()
    }

    public func inspectEnvironment() async {
        notificationPermission = await notifier.authorizationStatus()
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
            permissionRepairMessage = "权限已修复"
        } catch {
            permissionRepairMessage = "权限修复失败"
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
            await notifier.notifyLoginExpired()
        }
    }

    private func handleNetworkChange(available: Bool) {
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
