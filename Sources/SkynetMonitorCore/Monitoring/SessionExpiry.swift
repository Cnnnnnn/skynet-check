import Foundation

// The Skynet CLI does not yet report when a session expires
// (`skynet auth status --json` with expires is still missing), so expiry is
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

public struct SessionDurationStatistics: Equatable, Sendable {
    public let observationCount: Int
    public let average: TimeInterval
    public let shortest: TimeInterval

    public init(observationCount: Int, average: TimeInterval, shortest: TimeInterval) {
        self.observationCount = observationCount
        self.average = average
        self.shortest = shortest
    }
}

public extension SessionExpiryRecord {
    var statistics: SessionDurationStatistics? {
        guard !durations.isEmpty else {
            return nil
        }
        return SessionDurationStatistics(
            observationCount: durations.count,
            average: durations.reduce(0, +) / Double(durations.count),
            shortest: durations.min() ?? 0
        )
    }
}

public enum DurationPresentation {
    public static func summarize(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        if hours >= 1 {
            return String(format: "%.1f 小时", hours)
        }
        return "\(Int(interval / 60)) 分钟"
    }
}

// Panel / diagnostics copy for the estimated expiry. Once wall-clock passes
// the estimate the number is stale noise; keep it but say CLI wins.
public enum SessionExpiryPresentation {
    public static func panelLabel(expiresAt: Date, now: Date = Date()) -> String {
        let time = expiresAt.formatted(date: .omitted, time: .shortened)
        if expiresAt > now {
            return MonitorText.SessionExpiry.panelUpcoming(time)
        }
        return MonitorText.SessionExpiry.panelPast(time)
    }

    public static func diagnosticsLine(expiresAt: Date, now: Date = Date()) -> String {
        let stamp = expiresAt.formatted(date: .abbreviated, time: .shortened)
        if expiresAt > now {
            return MonitorText.SessionExpiry.diagnosticsUpcoming(stamp)
        }
        return MonitorText.SessionExpiry.diagnosticsPast(stamp)
    }

    // Compact menu-bar countdown ("2h10m"); nil once the estimate is in
    // the past, where the icon alone already says the rest.
    public static func menuBarCountdown(expiresAt: Date, now: Date = Date()) -> String? {
        let remaining = Int(expiresAt.timeIntervalSince(now))
        guard remaining > 0 else {
            return nil
        }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(max(minutes, 1))m"
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
            } else {
                raiseLiveFloor(at: date)
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

    // A session that outlives the shortest sample has already proven a
    // higher lower bound; bump that sample so the estimate cannot freeze
    // in the past while CLI still reports authenticated.
    private mutating func raiseLiveFloor(at date: Date) {
        guard let startedAt = record.lastAuthenticatedAt,
              let minIndex = record.durations.indices.min(by: {
                  record.durations[$0] < record.durations[$1]
              })
        else {
            return
        }
        let elapsed = date.timeIntervalSince(startedAt)
        if elapsed > record.durations[minIndex] {
            record.durations[minIndex] = elapsed
        }
    }

    public func estimatedExpiry(now: Date) -> Date? {
        guard let startedAt = record.lastAuthenticatedAt,
              let duration = record.conservativeDuration
        else {
            return nil
        }
        let estimated = startedAt.addingTimeInterval(duration)
        // Zero/negative remaining is not a useful deadline — hide it.
        guard estimated > now else {
            return nil
        }
        return estimated
    }

    // True when this login period has history but no future deadline left
    // (typically after raiseLiveFloor caught the estimate up to "now").
    public func hasOutlivedEstimate(now: Date) -> Bool {
        guard record.lastAuthenticatedAt != nil, !record.durations.isEmpty else {
            return false
        }
        return estimatedExpiry(now: now) == nil
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
        // Past the estimate while still authenticated means the heuristic
        // already failed; nagging "about to expire" would be a false alarm.
        guard remaining > 0 else {
            return nil
        }
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
