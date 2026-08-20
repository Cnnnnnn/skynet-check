import XCTest
@testable import SkynetMonitorCore

final class LoginActionNotificationTests: XCTestCase {
    func testAlreadyAuthenticatedMessageExplainsNoLoginPageWasNeeded() {
        XCTAssertEqual(
            LoginActionResult.alreadyAuthenticated(
                email: "user@example.com"
            ).notification,
            .init(
                title: "Skynet 当前已登录",
                body: "user@example.com 当前登录有效，无需重新登录。"
            )
        )
    }

    func testCompletedAuthenticationMessageReportsSuccess() {
        XCTAssertEqual(
            LoginActionResult.completed(
                .authenticated(email: "user@example.com")
            ).notification,
            .init(
                title: "Skynet 登录成功",
                body: "已登录为 user@example.com。"
            )
        )
    }

    func testCompletedFailureMessagesExplainNextAction() {
        XCTAssertEqual(
            LoginActionResult.completed(.offline).notification,
            .init(
                title: "Skynet 登录失败",
                body: "网络不可用，请恢复网络后重试。"
            )
        )
        XCTAssertEqual(
            LoginActionResult.completed(.cliMissing).notification,
            .init(
                title: "无法启动 Skynet 登录",
                body: "未找到 Skynet CLI。"
            )
        )
        XCTAssertEqual(
            LoginActionResult.completed(
                .serviceError(message: "ignored")
            ).notification,
            .init(
                title: "Skynet 登录失败",
                body: "登录服务暂时不可用，请稍后重试。"
            )
        )
    }
}
