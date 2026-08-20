import XCTest
@testable import SkynetMonitorCore

final class NotificationActionTests: XCTestCase {
    func testParsesSupportedNotificationActions() {
        XCTAssertEqual(
            LoginNotificationAction(rawValue: "skynet-login-now"),
            .login
        )
        XCTAssertEqual(
            LoginNotificationAction(rawValue: "skynet-check-now"),
            .check
        )
        XCTAssertNil(LoginNotificationAction(rawValue: "unknown"))
    }
}
