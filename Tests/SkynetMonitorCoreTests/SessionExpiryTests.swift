import Foundation
import XCTest
@testable import SkynetMonitorCore

final class SessionExpiryTests: XCTestCase {
    func testTrackerRecordsDurationWhenSessionDrops() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var tracker = SessionExpiryTracker()

        tracker.recordState(.authenticated(email: nil), at: start)
        tracker.recordState(.authenticated(email: nil), at: start.addingTimeInterval(600))
        tracker.recordState(
            .unauthenticated,
            at: start.addingTimeInterval(3600)
        )

        XCTAssertEqual(
            tracker.currentRecord.durations,
            [3600]
        )
        XCTAssertNil(tracker.currentRecord.lastAuthenticatedAt)
    }

    func testTrackerEstimatesUsingShortestObservation() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var tracker = SessionExpiryTracker(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: start,
                durations: [7200, 3600, 9000]
            )
        )

        XCTAssertEqual(
            tracker.estimatedExpiry(now: start),
            start.addingTimeInterval(3600)
        )
    }

    func testTrackerWithoutHistoryCannotEstimate() {
        var tracker = SessionExpiryTracker(
            record: SessionExpiryRecord(lastAuthenticatedAt: Date())
        )

        XCTAssertNil(tracker.estimatedExpiry(now: Date()))
    }

    func testTrackerKeepsOnlyRecentDurations() {
        var record = SessionExpiryRecord()
        for index in 0..<8 {
            record.durations.append(TimeInterval(1000 + index))
        }

        record.durations = Array(
            record.durations.suffix(SessionExpiryRecord.maxDurations)
        )

        XCTAssertEqual(record.durations.count, SessionExpiryRecord.maxDurations)
    }

    func testAdvisorNotifiesOncePerStagePerSession() {
        var advisor = SessionExpiryAdvisor()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionStart = now.addingTimeInterval(-7200)
        let expiryInTwoHours = now.addingTimeInterval(7200)

        XCTAssertNil(
            advisor.evaluate(
                estimatedExpiry: expiryInTwoHours,
                sessionStartedAt: sessionStart,
                now: now
            )
        )

        let expiryInHalfHour = now.addingTimeInterval(1800)
        XCTAssertEqual(
            advisor.evaluate(
                estimatedExpiry: expiryInHalfHour,
                sessionStartedAt: sessionStart,
                now: now
            ),
            .warning
        )
        XCTAssertNil(
            advisor.evaluate(
                estimatedExpiry: expiryInHalfHour,
                sessionStartedAt: sessionStart,
                now: now.addingTimeInterval(60)
            )
        )

        let expiryInFiveMinutes = now.addingTimeInterval(300)
        XCTAssertEqual(
            advisor.evaluate(
                estimatedExpiry: expiryInFiveMinutes,
                sessionStartedAt: sessionStart,
                now: now.addingTimeInterval(120)
            ),
            .urgent
        )
        XCTAssertNil(
            advisor.evaluate(
                estimatedExpiry: expiryInFiveMinutes,
                sessionStartedAt: sessionStart,
                now: now.addingTimeInterval(180)
            )
        )
    }

    func testAdvisorResetsForNewSessionAndForMissingEstimate() {
        var advisor = SessionExpiryAdvisor()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let firstSession = now.addingTimeInterval(-7200)

        _ = advisor.evaluate(
            estimatedExpiry: now.addingTimeInterval(1800),
            sessionStartedAt: firstSession,
            now: now
        )

        XCTAssertNil(
            advisor.evaluate(
                estimatedExpiry: nil,
                sessionStartedAt: nil,
                now: now
            )
        )

        let secondSession = now
        XCTAssertEqual(
            advisor.evaluate(
                estimatedExpiry: now.addingTimeInterval(1800),
                sessionStartedAt: secondSession,
                now: now
            ),
            .warning
        )
    }

    func testStoreRoundTripsRecord() {
        let suiteName = "SessionExpiryTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let store = SessionExpiryStore(defaults: UserDefaults(suiteName: suiteName)!)
        let record = SessionExpiryRecord(
            lastAuthenticatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durations: [3600, 7200]
        )

        store.save(record)

        XCTAssertEqual(store.load(), record)
    }

    func testStatisticsSummarizeObservedDurations() {
        let record = SessionExpiryRecord(durations: [3600, 7200, 10800])

        let statistics = record.statistics

        XCTAssertEqual(statistics?.observationCount, 3)
        XCTAssertEqual(statistics?.average ?? 0, 7200, accuracy: 1)
        XCTAssertEqual(statistics?.shortest, 3600)
        XCTAssertNil(SessionExpiryRecord(durations: []).statistics)
    }

    func testDurationPresentationFormatsHoursAndMinutes() {
        XCTAssertEqual(DurationPresentation.summarize(7200), "2.0 小时")
        XCTAssertEqual(DurationPresentation.summarize(45 * 60), "45 分钟")
        XCTAssertEqual(DurationPresentation.summarize(90 * 60), "1.5 小时")
    }
}
