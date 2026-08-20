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

    func testReadsOutputLargerThanPipeBufferWithoutDeadlocking() async {
        let result = await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", "head -c 262144 /dev/zero | base64"],
            environment: [:],
            timeout: .seconds(10)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertGreaterThan(result.stdout.count, 262_144)
    }

    func testStreamsLinesWhileCommandRuns() async {
        let collector = LockedLineCollector()
        let result = await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-c",
                "echo first; sleep 0.3; echo url https://login.example.com/abc",
            ],
            environment: [:],
            timeout: .seconds(10),
            onLine: { line in
                collector.append(line)
            }
        )

        let lines = collector.lines

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertTrue(lines.contains("first"))
        XCTAssertTrue(lines.contains("url https://login.example.com/abc"))
    }

    private final class LockedLineCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        var lines: [String] {
            lock.withLock { items }
        }

        func append(_ line: String) {
            lock.withLock {
                items.append(line)
            }
        }
    }

    func testKillsProcessThatIgnoresSIGTERM() async {
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", "trap '' TERM; sleep 30"],
            environment: [:],
            timeout: .milliseconds(100)
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(
            startedAt.duration(to: clock.now),
            .seconds(10)
        )
    }
}
