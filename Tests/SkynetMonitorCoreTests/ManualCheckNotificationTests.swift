import XCTest
import UserNotifications
@testable import SkynetMonitorCore

final class ManualCheckNotificationTests: XCTestCase {
    func testMapsAuthenticatedResultWithEmail() {
        XCTAssertEqual(
            LoginState.authenticated(email: "user@example.com").manualCheckNotification,
            .init(
                title: "Skynet 登录状态正常",
                body: "user@example.com 当前登录有效。"
            )
        )
    }

    func testMapsEveryNonCheckingFailureResult() {
        XCTAssertEqual(
            LoginState.unauthenticated.manualCheckNotification,
            .init(
                title: "Skynet 可能已退出登录",
                body: "将在 30 秒后自动复核。"
            )
        )
        XCTAssertEqual(
            LoginState.offline.manualCheckNotification,
            .init(
                title: "Skynet 暂时无法检查",
                body: "网络不可用，请恢复网络后重试。"
            )
        )
        XCTAssertEqual(
            LoginState.serviceError(message: "ignored").manualCheckNotification,
            .init(
                title: "Skynet 状态检查失败",
                body: "服务暂时不可用，请稍后重试。"
            )
        )
        XCTAssertEqual(
            LoginState.cliMissing.manualCheckNotification,
            .init(
                title: "未找到 Skynet CLI",
                body: "请确认 Skynet CLI 已安装并可在终端运行。"
            )
        )
    }

    func testCheckingStateHasNoCompletedResultNotification() {
        XCTAssertNil(LoginState.checking.manualCheckNotification)
    }

    func testForegroundNotificationUsesBannerAndSound() {
        XCTAssertEqual(
            NotificationPresentationPolicy.foregroundOptions,
            [.banner, .sound]
        )
    }
}
