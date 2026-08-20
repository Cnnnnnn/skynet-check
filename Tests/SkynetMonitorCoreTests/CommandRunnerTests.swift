import XCTest
@testable import SkynetMonitorCore

final class CommandRunnerTests: XCTestCase {
    func testCapturesStandardOutputAndExitCode() async {
        let result = await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ready"],
            environment: [:],
            timeout: .seconds(2)
        )

        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ready")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
    }

    func testTerminatesLongRunningProcessAtTimeout() async {
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            environment: [:],
            timeout: .milliseconds(100)
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(2))
    }
}
