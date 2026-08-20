public enum LoginTransitionAction: Equatable, Sendable {
    case none
    case confirmAfter(seconds: Int)
    case notifyExpired
}

// Every completed unauthenticated check advances the confirmation counter,
// including manual "check now" taps. Two independent unauthenticated
// results confirm a failure episode — whether they arrive via the scheduled
// 30-second recheck or the user checking twice — so an eager user confirms
// an expiry immediately instead of waiting for the timer.
public struct LoginTransitionTracker: Sendable {
    private var consecutiveUnauthenticated = 0
    private var notifiedForCurrentEpisode = false

    public init() {}

    public mutating func consume(_ state: LoginState) -> LoginTransitionAction {
        switch state {
        case .authenticated:
            consecutiveUnauthenticated = 0
            notifiedForCurrentEpisode = false
            return .none

        case .unauthenticated:
            guard !notifiedForCurrentEpisode else {
                return .none
            }

            consecutiveUnauthenticated += 1
            if consecutiveUnauthenticated == 1 {
                return .confirmAfter(seconds: 30)
            }

            notifiedForCurrentEpisode = true
            return .notifyExpired

        case .checking, .offline, .serviceError, .cliMissing:
            consecutiveUnauthenticated = 0
            return .none
        }
    }
}
