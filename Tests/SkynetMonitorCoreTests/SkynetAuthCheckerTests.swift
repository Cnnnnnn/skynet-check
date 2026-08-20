import Foundation
import XCTest
@testable import SkynetMonitorCore

final class SkynetAuthCheckerTests: XCTestCase {
    func testChecksAuthenticationWithNVMDirectoryPrependedToPath() async throws {
        let runner = RecordingCommandRunner(results: [
            .init(
                stdout: "认证状态: 已认证\n用户邮箱: user@example.com",
                stderr: "",
                exitCode: 0,
                timedOut: false
            ),
        ])
        let checker = makeChecker(runner: runner)

        let state = await checker.check(networkAvailable: true)
        let capturedInvocations = await runner.invocations

        XCTAssertEqual(state, .authenticated(email: "user@example.com"))
        let invocation = try XCTUnwrap(capturedInvocations.first)
        XCTAssertEqual(invocation.arguments, ["auth", "status"])
        XCTAssertEqual(
            invocation.environment["PATH"],
            "/fake/nvm/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
        XCTAssertEqual(invocation.timeout, .seconds(8))
    }

    func testReturnsCLIMissingWhenPathCannotBeResolved() async {
        let checker = SkynetAuthChecker(
            locator: StubPathLocator(missing: ()),
            runner: RecordingCommandRunner(results: [])
        )

        let state = await checker.check(networkAvailable: true)
        XCTAssertEqual(state, .cliMissing)
    }

    func testRefinesTimeoutToOfflineWhenNetworkIsUnavailable() async {
        let runner = RecordingCommandRunner(results: [
            .init(stdout: "", stderr: "", exitCode: 15, timedOut: true),
        ])
        let checker = makeChecker(runner: runner)

        let state = await checker.check(networkAvailable: false)
        XCTAssertEqual(state, .offline)
    }

    func testLoginRunsLoginThenChecksStatus() async throws {
        let runner = RecordingCommandRunner(results: [
            .init(stdout: "login complete", stderr: "", exitCode: 0, timedOut: false),
            .init(stdout: "认证状态: 已认证", stderr: "", exitCode: 0, timedOut: false),
        ])
        let checker = makeChecker(runner: runner)

        let state = await checker.login(networkAvailable: true)

        XCTAssertEqual(state, .authenticated(email: nil))
        let invocations = await runner.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["auth", "login"], ["auth", "status"]])
        XCTAssertEqual(invocations.first?.timeout, .seconds(60))
    }

    func testReadsTrimmedCLIVersion() async {
        let runner = RecordingCommandRunner(results: [
            .init(stdout: "2.7.29\n", stderr: "", exitCode: 0, timedOut: false),
        ])
        let checker = makeChecker(runner: runner)

        let version = await checker.version()
        XCTAssertEqual(version, "2.7.29")
    }

    private func makeChecker(runner: RecordingCommandRunner) -> SkynetAuthChecker {
        SkynetAuthChecker(
            locator: StubPathLocator(
                url: URL(fileURLWithPath: "/fake/nvm/bin/skynet")
            ),
            runner: runner,
            baseEnvironment: ["LANG": "zh_CN.UTF-8"]
        )
    }
}

private struct StubPathLocator: CLIPathLocating {
    let url: URL?

    init(url: URL) {
        self.url = url
    }

    init(missing: Void) {
        self.url = nil
    }

    func locate() async throws -> URL {
        guard let url else {
            throw CLIPathError.notFound
        }
        return url
    }
}

private actor RecordingCommandRunner: CommandRunning {
    struct Invocation: Sendable {
        let arguments: [String]
        let environment: [String: String]
        let timeout: Duration
    }

    private var results: [CommandResult]
    private(set) var invocations: [Invocation] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        invocations.append(
            Invocation(
                arguments: arguments,
                environment: environment,
                timeout: timeout
            )
        )
        return results.removeFirst()
    }
}
