import XCTest
@testable import SkynetMonitorCore

final class LoginTransitionTrackerTests: XCTestCase {
    func testNotifiesOnlyAfterTwoConsecutiveUnauthenticatedResults() {
        var tracker = LoginTransitionTracker()

        XCTAssertEqual(
            tracker.consume(.unauthenticated),
            .confirmAfter(seconds: 30)
        )
        XCTAssertEqual(tracker.consume(.unauthenticated), .notifyExpired)
        XCTAssertEqual(tracker.consume(.unauthenticated), .none)
    }

    func testAuthenticatedRecoveryRearmsNotification() {
        var tracker = LoginTransitionTracker()
        _ = tracker.consume(.unauthenticated)
        _ = tracker.consume(.unauthenticated)

        XCTAssertEqual(tracker.consume(.authenticated(email: nil)), .none)
        XCTAssertEqual(
            tracker.consume(.unauthenticated),
            .confirmAfter(seconds: 30)
        )
        XCTAssertEqual(tracker.consume(.unauthenticated), .notifyExpired)
    }

    func testOfflineBreaksConsecutiveFailureSequence() {
        var tracker = LoginTransitionTracker()

        XCTAssertEqual(
            tracker.consume(.unauthenticated),
            .confirmAfter(seconds: 30)
        )
        XCTAssertEqual(tracker.consume(.offline), .none)
        XCTAssertEqual(
            tracker.consume(.unauthenticated),
            .confirmAfter(seconds: 30)
        )
    }

    func testServiceErrorAndCLIMissingNeverNotify() {
        var tracker = LoginTransitionTracker()

        XCTAssertEqual(
            tracker.consume(.serviceError(message: "unavailable")),
            .none
        )
        XCTAssertEqual(tracker.consume(.cliMissing), .none)
    }
}
