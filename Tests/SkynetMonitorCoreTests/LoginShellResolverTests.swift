import Foundation
import XCTest
@testable import SkynetMonitorCore

final class LoginShellResolverTests: XCTestCase {
    func testPrefersNonInteractiveLoginShell() async {
        let runner = SequencedCommandRunner(results: [
            .success(stdout: "/opt/homebrew/bin/skynet\n")
        ])
        let resolver = LoginShellResolver(runner: runner)

        let output = await resolver.resolve(command: "command -v skynet")
        let invocations = await runner.invocations

        XCTAssertEqual(output, "/opt/homebrew/bin/skynet")
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].arguments, ["-l", "-c", "command -v skynet"])
    }

    func testFallsBackToInteractiveShellWhenNonInteractiveFails() async {
        let runner = SequencedCommandRunner(results: [
            .init(stdout: "", stderr: "command not found", exitCode: 127, timedOut: false),
            .success(stdout: "/nvm/bin/skynet\n"),
        ])
        let resolver = LoginShellResolver(runner: runner)

        let output = await resolver.resolve(command: "command -v skynet")
        let invocations = await runner.invocations

        XCTAssertEqual(output, "/nvm/bin/skynet")
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(
            invocations[1].arguments,
            ["-l", "-i", "-c", "command -v skynet"]
        )
    }

    func testRetriesInteractiveShellWhenNonInteractiveProducesNoOutput() async {
        let runner = SequencedCommandRunner(results: [
            .success(stdout: "  \n"),
            .success(stdout: "v20.11.0\n"),
        ])
        let resolver = LoginShellResolver(runner: runner)

        let output = await resolver.resolve(command: "node --version")

        XCTAssertEqual(output, "v20.11.0")
    }

    func testReturnsNilWhenAllModesFail() async {
        let runner = SequencedCommandRunner(results: [
            .init(stdout: "", stderr: "", exitCode: 1, timedOut: false),
            .init(stdout: "", stderr: "", exitCode: 1, timedOut: true),
        ])
        let resolver = LoginShellResolver(runner: runner)

        let output = await resolver.resolve(command: "command -v skynet")

        XCTAssertNil(output)
    }
}

private actor SequencedCommandRunner: CommandRunning {
    struct Invocation: Sendable {
        let arguments: [String]
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
        invocations.append(Invocation(arguments: arguments))
        return results.isEmpty
            ? CommandResult(stdout: "", stderr: "", exitCode: 1, timedOut: false)
            : results.removeFirst()
    }
}

private extension CommandResult {
    static func success(stdout: String) -> Self {
        .init(stdout: stdout, stderr: "", exitCode: 0, timedOut: false)
    }
}
