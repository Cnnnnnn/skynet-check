import XCTest
@testable import SkynetMonitorCore

final class AuthOutputParserTests: XCTestCase {
    func testParsesAuthenticatedChineseOutput() {
        XCTAssertEqual(
            AuthOutputParser.parse(
                AuthOutput(
                    stdout: "🔍 认证状态: 已认证\n🔍 用户邮箱: user@example.com",
                    stderr: "",
                    exitCode: 0,
                    timedOut: false
                )
            ),
            .authenticated(email: "user@example.com")
        )
    }

    func testParsesAuthenticatedEnglishOutput() {
        XCTAssertEqual(
            AuthOutputParser.parse(
                AuthOutput(
                    stdout: "Authentication Status: Authenticated\nUser Email: user@example.com",
                    stderr: "",
                    exitCode: 0,
                    timedOut: false
                )
            ),
            .authenticated(email: "user@example.com")
        )
    }

    func testParsesChineseLoginPromptAsUnauthenticated() {
        XCTAssertEqual(
            AuthOutputParser.parse(
                AuthOutput(
                    stdout: "使用 'skynet auth login' 进行登录",
                    stderr: "",
                    exitCode: 0,
                    timedOut: false
                )
            ),
            .unauthenticated
        )
    }

    func testDoesNotTreatNotAuthenticatedAsAuthenticatedSubstring() {
        XCTAssertEqual(
            AuthOutputParser.parse(
                AuthOutput(
                    stdout: "Authentication Status: Not Authenticated",
                    stderr: "",
                    exitCode: 0,
                    timedOut: false
                )
            ),
            .unauthenticated
        )
    }

    func testRejectsUnrecognizedOutputWithoutEchoingIt() {
        XCTAssertEqual(
            AuthOutputParser.parse(
                AuthOutput(
                    stdout: "unexpected-sensitive-output",
                    stderr: "",
                    exitCode: 0,
                    timedOut: false
                )
            ),
            .serviceError(message: "Unrecognized Skynet CLI response")
        )
    }

    func testClassifiesTimeoutBeforeOutput() {
        XCTAssertEqual(
            AuthOutputParser.parse(
                AuthOutput(
                    stdout: "认证状态: 已认证",
                    stderr: "",
                    exitCode: 0,
                    timedOut: true
                )
            ),
            .serviceError(message: "Skynet CLI timed out")
        )
    }
}
