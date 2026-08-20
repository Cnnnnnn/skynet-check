import Foundation
import Network

@MainActor
public protocol NetworkMonitoring: AnyObject {
    var isAvailable: Bool { get }
    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void)
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

    public init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.isAvailable = monitor.currentPath.status == .satisfied
    }

    public func start(
        onChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard !started else {
            return
        }
        started = true
        self.onChange = onChange

        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let changed = self.isAvailable != available
                self.isAvailable = available
                if changed {
                    self.onChange?(available)
                }
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        guard started else {
            return
        }
        started = false
        monitor.cancel()
        onChange = nil
    }
}
