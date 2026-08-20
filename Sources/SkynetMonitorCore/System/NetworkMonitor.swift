import Foundation
import Network

@MainActor
public protocol NetworkMonitoring: AnyObject {
    var isAvailable: Bool { get }
    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) async
    func stop()
}

@MainActor
public final class NetworkMonitor: NetworkMonitoring {
    public private(set) var isAvailable: Bool

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(
        label: "io.skynet.login-monitor.network"
    )
    private var onChange: (@MainActor @Sendable (Bool) -> Void)?
    private var started = false
    private var initialPathContinuation: CheckedContinuation<Void, Never>?

    public init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        // NWPathMonitor reports .unsatisfied until started; the first path
        // update delivered by start(onChange:) overwrites this placeholder.
        self.isAvailable = false
    }

    public func start(
        onChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) async {
        guard !started else {
            return
        }
        started = true
        self.onChange = onChange

        await withCheckedContinuation { continuation in
            initialPathContinuation = continuation
            monitor.pathUpdateHandler = { [weak self] path in
                let available = path.status == .satisfied
                Task { @MainActor [weak self] in
                    self?.handlePathUpdate(available: available)
                }
            }
            monitor.start(queue: queue)
        }
    }

    public func stop() {
        guard started else {
            return
        }
        started = false
        monitor.cancel()
        onChange = nil
        if let initialPathContinuation {
            self.initialPathContinuation = nil
            initialPathContinuation.resume()
        }
    }

    private func handlePathUpdate(available: Bool) {
        let wasAvailable = isAvailable
        isAvailable = available
        guard let initialPathContinuation else {
            if wasAvailable != available {
                onChange?(available)
            }
            return
        }

        // The first update establishes the initial state rather than a
        // transition; callers run their own initial check after start.
        self.initialPathContinuation = nil
        initialPathContinuation.resume()
    }
}
