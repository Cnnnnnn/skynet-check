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

    func testDefaultTapActionMapsByNotificationKind() {
        XCTAssertEqual(
            NotificationActionRouting.defaultAction(
                categoryIdentifier: "skynet-login-actions",
                identifier: "skynet-login-expired"
            ),
            .login
        )
        XCTAssertEqual(
            NotificationActionRouting.defaultAction(
                categoryIdentifier: "skynet-login-actions",
                identifier: "skynet-session-expiring"
            ),
            .login
        )
        XCTAssertEqual(
            NotificationActionRouting.defaultAction(
                categoryIdentifier: "",
                identifier: "skynet-manual-check"
            ),
            .check
        )
        XCTAssertNil(
            NotificationActionRouting.defaultAction(
                categoryIdentifier: "",
                identifier: "skynet-token-invalid-CONFLUENCE_TOKEN"
            )
        )
        XCTAssertNil(
            NotificationActionRouting.defaultAction(
                categoryIdentifier: "",
                identifier: "skynet-login-action"
            )
        )
    }
}
