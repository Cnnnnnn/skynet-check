import Foundation

// A persisted do-not-disturb window: while `pausedUntil` is in the future,
// the notifier drops notifications (checks keep running and the panel stays
// live). Survives app restarts so "暂停 1 小时" before a meeting is not
// undone by a relaunch.
public struct NotificationMuteWindow: Codable, Equatable, Sendable {
    public let pausedUntil: Date

    public init(pausedUntil: Date) {
        self.pausedUntil = pausedUntil
    }

    // Standard preset durations offered by the panel.
    public static let presets: [TimeInterval] = [30 * 60, 60 * 60, 4 * 60 * 60]

    public static func isActive(
        _ window: NotificationMuteWindow?,
        now: Date
    ) -> Bool {
        guard let window else {
            return false
        }
        return window.pausedUntil > now
    }

    public static func storageKey(in defaults: UserDefaults) -> Data? {
        defaults.data(forKey: "notificationMuteWindow")
    }
}

public final class NotificationMuteStore: @unchecked Sendable {
    private static let key = "notificationMuteWindow"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> NotificationMuteWindow? {
        guard let data = defaults.data(forKey: Self.key),
              let window = try? Self.decoder.decode(NotificationMuteWindow.self, from: data),
              NotificationMuteWindow.isActive(window, now: Date())
        else {
            return nil
        }
        return window
    }

    public func pause(until date: Date) {
        guard let data = try? Self.encoder.encode(NotificationMuteWindow(pausedUntil: date)) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func resume() {
        defaults.removeObject(forKey: Self.key)
    }
}
