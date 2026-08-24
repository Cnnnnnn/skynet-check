import XCTest
@testable import SkynetMonitorCore

final class MenuBarCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(
            SessionExpiryPresentation.menuBarCountdown(
                expiresAt: now.addingTimeInterval(2 * 3600 + 10 * 60),
                now: now
            ),
            "2h10m"
        )
    }

    func testUnderAnHourShowsMinutesOnly() {
        XCTAssertEqual(
            SessionExpiryPresentation.menuBarCountdown(
                expiresAt: now.addingTimeInterval(45 * 60),
                now: now
            ),
            "45m"
        )
    }

    func testSubMinuteRoundsUpToOneMinute() {
        XCTAssertEqual(
            SessionExpiryPresentation.menuBarCountdown(
                expiresAt: now.addingTimeInterval(20),
                now: now
            ),
            "1m"
        )
    }

    func testPastEstimateReturnsNil() {
        XCTAssertNil(
            SessionExpiryPresentation.menuBarCountdown(
                expiresAt: now.addingTimeInterval(-60),
                now: now
            )
        )
    }
}
