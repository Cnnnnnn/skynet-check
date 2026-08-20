import XCTest
@testable import SkynetMonitorCore

final class NotificationEnvironmentTests: XCTestCase {
    func testRequiresApplicationBundleAndIdentifier() {
        XCTAssertFalse(
            NotificationEnvironment.supportsUserNotifications(
                bundleURL: URL(fileURLWithPath: "/tmp/debug/"),
                bundleIdentifier: "io.skynet.login-monitor"
            )
        )
        XCTAssertFalse(
            NotificationEnvironment.supportsUserNotifications(
                bundleURL: URL(fileURLWithPath: "/tmp/Skynet Login Monitor.app"),
                bundleIdentifier: nil
            )
        )
        XCTAssertTrue(
            NotificationEnvironment.supportsUserNotifications(
                bundleURL: URL(fileURLWithPath: "/tmp/Skynet Login Monitor.app"),
                bundleIdentifier: "io.skynet.login-monitor"
            )
        )
    }
}
