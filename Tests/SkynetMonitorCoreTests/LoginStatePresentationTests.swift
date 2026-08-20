import XCTest
@testable import SkynetMonitorCore

final class LoginStatePresentationTests: XCTestCase {
    func testMapsEveryStateToStableMenuCopyAndSymbol() {
        XCTAssertEqual(
            LoginState.checking.presentation,
            .init(title: "正在检查", symbolName: "circle.dotted", tint: .secondary)
        )
        XCTAssertEqual(
            LoginState.authenticated(email: "user@example.com").presentation,
            .init(title: "已登录", symbolName: "checkmark.circle.fill", tint: .green)
        )
        XCTAssertEqual(
            LoginState.unauthenticated.presentation,
            .init(
                title: "登录已失效",
                symbolName: "exclamationmark.circle.fill",
                tint: .red
            )
        )
        XCTAssertEqual(
            LoginState.offline.presentation,
            .init(
                title: "网络不可用",
                symbolName: "wifi.exclamationmark",
                tint: .yellow
            )
        )
        XCTAssertEqual(
            LoginState.serviceError(message: "ignored").presentation,
            .init(
                title: "暂时无法检查",
                symbolName: "wifi.exclamationmark",
                tint: .yellow
            )
        )
        XCTAssertEqual(
            LoginState.cliMissing.presentation,
            .init(
                title: "未找到 Skynet CLI",
                symbolName: "questionmark.circle",
                tint: .secondary
            )
        )
    }

    func testExposesEmailOnlyForAuthenticatedState() {
        XCTAssertEqual(
            LoginState.authenticated(email: "user@example.com").authenticatedEmail,
            "user@example.com"
        )
        XCTAssertNil(LoginState.unauthenticated.authenticatedEmail)
    }
}
