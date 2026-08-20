import Foundation

// The Skynet CLI does not report when a session expires, so expiry is
// estimated instead: the tracker observes how long past authenticated
// periods lasted and reuses the shortest observation as a conservative
// estimate for the current session.

public struct SessionExpiryRecord: Codable, Equatable, Sendable {
    public var lastAuthenticatedAt: Date?
    public var durations: [TimeInterval]

    public init(
        lastAuthenticatedAt: Date? = nil,
        durations: [TimeInterval] = []
    ) {
        self.lastAuthenticatedAt = lastAuthenticatedAt
        self.durations = durations
    }

    static let maxDurations = 5

    public var conservativeDuration: TimeInterval? {
        durations.min()
    }
}

public protocol SessionExpiryStoring: AnyObject, Sendable {
    func load() -> SessionExpiryRecord?
    func save(_ record: SessionExpiryRecord)
}

public final class SessionExpiryStore: SessionExpiryStoring, @unchecked Sendable {
    private static let storageKey = "sessionExpiryRecord"
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

    public func load() -> SessionExpiryRecord? {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try? Self.decoder.decode(SessionExpiryRecord.self, from: data)
    }

    public func save(_ record: SessionExpiryRecord) {
        guard let data = try? Self.encoder.encode(record) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

public struct SessionExpiryTracker: Sendable {
    private var record: SessionExpiryRecord

    public init(record: SessionExpiryRecord = SessionExpiryRecord()) {
        self.record = record
    }

    public var currentRecord: SessionExpiryRecord {
        record
    }

    // Feed every completed check result in. A fresh authenticated period
    // starts when authentication appears after being absent; a duration is
    // captured when the session drops to unauthenticated. Cold starts
    // timestamp the session late, which biases estimates later rather than
    // earlier — documented and accepted.
    public mutating func recordState(_ state: LoginState, at date: Date) {
        switch state {
        case .authenticated:
            if record.lastAuthenticatedAt == nil {
                record.lastAuthenticatedAt = date
            }
        case .unauthenticated:
            if let startedAt = record.lastAuthenticatedAt {
                let duration = date.timeIntervalSince(startedAt)
                if duration > 0 {
                    record.durations.append(duration)
                    record.durations = Array(
                        record.durations.suffix(SessionExpiryRecord.maxDurations)
                    )
                }
                record.lastAuthenticatedAt = nil
            }
        case .checking, .offline, .serviceError, .cliMissing:
            break
        }
    }

    public func estimatedExpiry(now: Date) -> Date? {
        guard let startedAt = record.lastAuthenticatedAt,
              let duration = record.conservativeDuration
        else {
            return nil
        }
        return startedAt.addingTimeInterval(duration)
    }
}

public struct SessionExpiryAdvisor: Sendable {
    public enum Stage: Int, Comparable, Sendable {
        case urgent
        case warning

        public static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var logLabel: String {
            switch self {
            case .warning:
                "warning"
            case .urgent:
                "urgent"
            }
        }
    }

    public static let warningInterval: TimeInterval = 60 * 60
    public static let urgentInterval: TimeInterval = 15 * 60

    private var notifiedForSessionStartedAt: Date?
    private var notifiedStages: Set<Stage> = []

    public init() {}

    // Returns the stage to notify for now, at most once per stage per
    // login session; a nil estimated expiry resets the dedup state.
    public mutating func evaluate(
        estimatedExpiry: Date?,
        sessionStartedAt: Date?,
        now: Date
    ) -> Stage? {
        guard let estimatedExpiry else {
            notifiedForSessionStartedAt = nil
            notifiedStages = []
            return nil
        }

        if notifiedForSessionStartedAt != sessionStartedAt {
            notifiedForSessionStartedAt = sessionStartedAt
            notifiedStages = []
        }

        let remaining = estimatedExpiry.timeIntervalSince(now)
        if remaining <= Self.urgentInterval, !notifiedStages.contains(.urgent) {
            notifiedStages.insert(.urgent)
            return .urgent
        }
        if remaining <= Self.warningInterval, !notifiedStages.contains(.warning) {
            notifiedStages.insert(.warning)
            return .warning
        }
        return nil
    }
}
