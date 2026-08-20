import UserNotifications
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

    func testMapsAuthorizationStatusesToPermissionStates() {
        XCTAssertEqual(
            NotificationPermissionMapper.status(from: .authorized),
            .authorized
        )
        XCTAssertEqual(
            NotificationPermissionMapper.status(from: .provisional),
            .authorized
        )
        XCTAssertEqual(
            NotificationPermissionMapper.status(from: .denied),
            .denied
        )
        XCTAssertEqual(
            NotificationPermissionMapper.status(from: .notDetermined),
            .notDetermined
        )
    }
}
