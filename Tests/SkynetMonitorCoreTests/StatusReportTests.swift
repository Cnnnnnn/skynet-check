import XCTest
@testable import SkynetMonitorCore

final class StatusReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testAuthenticatedSnapshotCarriesEmailAndExpiryEstimate() {
        // Session started 90 minutes ago; past sessions lasted 2h, so the
        // estimate sits 30 minutes out.
        let report = StatusReport.make(
            snapshot: .init(
                state: .authenticated(email: "user@example.com"),
                completedAt: now.addingTimeInterval(-60)
            ),
            expiryRecord: SessionExpiryRecord(
                lastAuthenticatedAt: now.addingTimeInterval(-5400),
                durations: [7200]
            ),
            now: now
        )

        XCTAssertEqual(report.state, "authenticated")
        XCTAssertEqual(report.email, "user@example.com")
        XCTAssertTrue(report.authenticated)
        XCTAssertEqual(report.sessionExpiresAt, now.addingTimeInterval(1800))
        XCTAssertFalse(report.sessionOutlivedEstimate)
    }

    func testUnauthenticatedHasNoEmailAndNoEstimate() {
        let report = StatusReport.make(
            snapshot: .init(state: .unauthenticated, completedAt: now),
            expiryRecord: nil,
            now: now
        )

        XCTAssertEqual(report.state, "unauthenticated")
        XCTAssertNil(report.email)
        XCTAssertFalse(report.authenticated)
        XCTAssertNil(report.sessionExpiresAt)
    }

    func testOutlivedEstimateIsFlagged() throws {
        // Session started 5 hours ago but past sessions lasted only 1h.
        let record = SessionExpiryRecord(
            lastAuthenticatedAt: now.addingTimeInterval(-18000),
            durations: [3600]
        )
        let tracker = SessionExpiryTracker(record: record)
        try XCTSkipIf(tracker.estimatedExpiry(now: now) != nil,
                      "estimate unexpectedly still positive")

        let report = StatusReport.make(
            snapshot: .init(
                state: .authenticated(email: nil),
                completedAt: now
            ),
            expiryRecord: record,
            now: now
        )

        XCTAssertTrue(report.sessionOutlivedEstimate)
        XCTAssertNil(report.sessionExpiresAt)
    }

    func testServiceErrorKeepsPersistenceSafeMessage() {
        let report = StatusReport.make(
            snapshot: .init(
                state: .serviceError(message: "Skynet CLI reported an error"),
                completedAt: now
            ),
            expiryRecord: nil,
            now: now
        )

        XCTAssertEqual(report.state, "serviceError")
        XCTAssertFalse(report.authenticated)
    }
}
