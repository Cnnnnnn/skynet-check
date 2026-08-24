import XCTest
@testable import SkynetMonitorCore

final class NotificationMuteWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNilWindowIsNeverActive() {
        XCTAssertFalse(NotificationMuteWindow.isActive(nil, now: now))
    }

    func testFutureDeadlineIsActivePastDeadlineIsNot() {
        let active = NotificationMuteWindow(pausedUntil: now.addingTimeInterval(60))
        XCTAssertTrue(NotificationMuteWindow.isActive(active, now: now))
        XCTAssertFalse(
            NotificationMuteWindow.isActive(active, now: now.addingTimeInterval(61)),
            "window expires once the deadline passes"
        )
    }

    func testStoreRoundTripsAndResumeClears() {
        let suite = "mute-window-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationMuteStore(defaults: defaults)

        XCTAssertNil(store.load(), "no window persisted initially")

        // A future deadline survives a save/load round trip. Dates encode
        // as whole seconds, so compare with second-level accuracy.
        let deadline = Date().addingTimeInterval(1800)
        store.pause(until: deadline)
        XCTAssertEqual(
            store.load()?.pausedUntil.timeIntervalSince1970 ?? 0,
            deadline.timeIntervalSince1970,
            accuracy: 1.0
        )

        // An expired persisted window reads as inactive.
        store.pause(until: Date().addingTimeInterval(-60))
        XCTAssertNil(store.load())

        store.resume()
        XCTAssertNil(store.load())
    }

    func testSuppressionCountingLifecycle() {
        let suite = "mute-suppression-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationMuteStore(defaults: defaults)

        // While muted, takeSummary reports nothing and keeps counting.
        store.pause(until: Date().addingTimeInterval(1800))
        store.recordSuppressed()
        store.recordSuppressed()
        XCTAssertNil(store.takeSuppressionSummary(now: Date()))

        // After the window expires, the summary surfaces once then resets.
        store.pause(until: Date().addingTimeInterval(-60))
        XCTAssertEqual(store.takeSuppressionSummary(now: Date()), 2)
        XCTAssertNil(store.takeSuppressionSummary(now: Date()))

        // An explicit resume clears silently (no stale count).
        store.pause(until: Date().addingTimeInterval(1800))
        store.recordSuppressed()
        store.resume()
        XCTAssertNil(store.takeSuppressionSummary(now: Date()))
    }
}
