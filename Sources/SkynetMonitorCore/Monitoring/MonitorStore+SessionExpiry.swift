import Foundation

// Session-expiry estimation, statistics and expiry notifications. Split
// from MonitorStore.swift to keep each file focused; these members share
// the store's MainActor state by design.
extension MonitorStore {
    func handleSessionExpiry(_ result: LoginState, at date: Date) async {
        expiryTracker.recordState(result, at: date)
        sessionExpiryStore?.save(expiryTracker.currentRecord)
        let estimatedExpiry = expiryTracker.estimatedExpiry(now: date)
        sessionExpiresAt = estimatedExpiry
        sessionExpiryOutlived = expiryTracker.hasOutlivedEstimate(now: date)
        sessionStatistics = expiryTracker.currentRecord.statistics

        let sessionStartedAt = expiryTracker.currentRecord.lastAuthenticatedAt
        if let stage = expiryAdvisor.evaluate(
            estimatedExpiry: estimatedExpiry,
            sessionStartedAt: sessionStartedAt,
            now: date
        ), let estimatedExpiry {
            MonitorLog.store.notice(
                "session expiry estimate crossed a threshold (\(stage.logLabel, privacy: .public))"
            )
            await notifier.notifySessionExpiring(
                stage: stage,
                expiresAt: estimatedExpiry
            )
        }
    }

    public func resetSessionStatistics() {
        // Keep the current login period; only forget the observed durations
        // so a corrupted sample no longer skews the expiry estimate.
        expiryTracker = SessionExpiryTracker(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: expiryTracker.currentRecord.lastAuthenticatedAt
            )
        )
        sessionExpiryStore?.save(expiryTracker.currentRecord)
        sessionStatistics = nil
        sessionExpiresAt = expiryTracker.estimatedExpiry(now: now())
        sessionExpiryOutlived = expiryTracker.hasOutlivedEstimate(now: now())
        MonitorLog.store.info("session duration statistics reset")
    }
}
