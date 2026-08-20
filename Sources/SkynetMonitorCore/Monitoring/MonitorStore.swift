import Combine
import Foundation

@MainActor
public final class MonitorStore: ObservableObject {
    @Published public private(set) var state: LoginState = .checking
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var cliVersion: String?
    @Published public private(set) var isChecking = false

    private let checker: any SkynetAuthChecking
    private let networkMonitor: any NetworkMonitoring
    private let notifier: any LoginNotifying
    private let periodicInterval: Duration?
    private let confirmationDelay: Duration

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
        confirmationDelay: Duration = .seconds(30)
    ) {
        self.checker = checker
        self.networkMonitor = networkMonitor
        self.notifier = notifier
        self.periodicInterval = periodicInterval
        self.confirmationDelay = confirmationDelay
    }

    public func start() async {
        guard !started else {
            return
        }
        started = true

        await notifier.requestAuthorization()
        networkMonitor.start { [weak self] available in
            self?.handleNetworkChange(available: available)
        }

        cliVersion = await checker.version()
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
        let result = await checker.login(
            networkAvailable: networkMonitor.isAvailable
        )
        state = result
        lastCheckedAt = Date()
        isChecking = false
        await handleTransition(result)
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
        networkMonitor.stop()
        started = false
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
        guard periodicTask == nil, let periodicInterval else {
            return
        }

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: periodicInterval)
                guard !Task.isCancelled else {
                    return
                }
                await self?.refresh()
            }
        }
    }
}
