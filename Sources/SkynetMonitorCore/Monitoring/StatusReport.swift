import Foundation

// Machine-readable status report behind the `skynet-status --json` command:
// scripts and agents read this instead of parsing `skynet auth status`
// output themselves. Built from the snapshots the running app persists —
// no CLI probes, no notifications.
public struct StatusReport: Encodable, Equatable {
    public let state: String
    public let email: String?
    public let authenticated: Bool
    public let checkedAt: Date
    public let sessionExpiresAt: Date?
    public let sessionOutlivedEstimate: Bool

    public static func make(
        snapshot: LoginStateSnapshot,
        expiryRecord: SessionExpiryRecord?,
        now: Date
    ) -> StatusReport {
        var expiresAt: Date?
        var outlived = false
        if let record = expiryRecord {
            let tracker = SessionExpiryTracker(record: record)
            if let estimate = tracker.estimatedExpiry(now: now) {
                expiresAt = estimate
            } else {
                outlived = tracker.hasOutlivedEstimate(now: now)
            }
        }
        return StatusReport(
            state: Self.stateLabel(snapshot.state),
            email: snapshot.state.authenticatedEmail,
            authenticated: snapshot.state.isAuthenticated,
            checkedAt: snapshot.completedAt,
            sessionExpiresAt: expiresAt,
            sessionOutlivedEstimate: outlived
        )
    }

    private static func stateLabel(_ state: LoginState) -> String {
        switch state {
        case .checking:
            "checking"
        case .authenticated:
            "authenticated"
        case .unauthenticated:
            "unauthenticated"
        case .offline:
            "offline"
        case .serviceError:
            "serviceError"
        case .cliMissing:
            "cliMissing"
        }
    }
}
