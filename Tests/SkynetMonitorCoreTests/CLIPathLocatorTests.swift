import Foundation
import XCTest
@testable import SkynetMonitorCore

final class CLIPathLocatorTests: XCTestCase {
    func testUsesExecutableCachedPathWithoutRunningShell() async throws {
        let suiteName = makeSuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("/bin/echo", forKey: "resolvedSkynetCLIPath")
        let runner = FakeCommandRunner(result: .success(stdout: "/not/used"))
        let locator = CLIPathLocator(runner: runner, defaultsSuiteName: suiteName)

        let url = try await locator.locate()
        let callCount = await runner.callCount

        XCTAssertEqual(url.path, "/bin/echo")
        XCTAssertEqual(callCount, 0)
    }

    func testDiscoversAndCachesExecutableFromLoginShell() async throws {
        let executable = try makeExecutable()
        let suiteName = makeSuiteName()
        let runner = FakeCommandRunner(result: .success(stdout: executable.path + "\n"))
        let locator = CLIPathLocator(runner: runner, defaultsSuiteName: suiteName)

        let url = try await locator.locate()
        let capturedInvocation = await runner.lastInvocation

        XCTAssertEqual(url, executable)
        XCTAssertEqual(
            UserDefaults(suiteName: suiteName)?.string(forKey: "resolvedSkynetCLIPath"),
            executable.path
        )
        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertEqual(invocation.executableURL.path, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-l", "-i", "-c", "command -v skynet"])
    }

    func testThrowsNotFoundForMissingShellResult() async {
        let suiteName = makeSuiteName()
        let locator = CLIPathLocator(
            runner: FakeCommandRunner(result: .success(stdout: "")),
            defaultsSuiteName: suiteName
        )

        do {
            _ = try await locator.locate()
            XCTFail("Expected CLIPathError.notFound")
        } catch {
            XCTAssertEqual(error as? CLIPathError, .notFound)
        }
    }

    private func makeSuiteName() -> String {
        let suiteName = "CLIPathLocatorTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return suiteName
    }

    private func makeExecutable() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("skynet")
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }
}

private actor FakeCommandRunner: CommandRunning {
    struct Invocation: Sendable {
        let executableURL: URL
        let arguments: [String]
    }

    private let result: CommandResult
    private(set) var callCount = 0
    private(set) var lastInvocation: Invocation?

    init(result: CommandResult) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        callCount += 1
        lastInvocation = Invocation(
            executableURL: executableURL,
            arguments: arguments
        )
        return result
    }
}

private extension CommandResult {
    static func success(stdout: String) -> Self {
        .init(
            stdout: stdout,
            stderr: "",
            exitCode: 0,
            timedOut: false
        )
    }
}
