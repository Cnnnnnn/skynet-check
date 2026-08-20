import Foundation

public final class PollingInterval {
    public static let minimumMinutes = 3
    public static let maximumMinutes = 60
    public static let defaultMinutes = 15
    public static let storageKey = "pollingIntervalMinutes"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var minutes: Int {
        let stored = defaults.integer(forKey: Self.storageKey)
        return stored == 0 ? Self.defaultMinutes : Self.clamped(stored)
    }

    public func setMinutes(_ minutes: Int) {
        defaults.set(Self.clamped(minutes), forKey: Self.storageKey)
    }

    public static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, minimumMinutes), maximumMinutes)
    }
}
