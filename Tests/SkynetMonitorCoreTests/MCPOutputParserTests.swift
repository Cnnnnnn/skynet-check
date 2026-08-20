import Foundation
import XCTest
@testable import SkynetMonitorCore

final class MCPOutputParserTests: XCTestCase {
    private let mcpListOutput = """
        ✅ 找到 5 个 Skynet MCP:

        📋 ────────────────────────────────────────────────────────────
        [Cursor] (3)
        📋 ────────────────────────────────────────────────────────────
        1. skynet-base (v2.11.5)
        2. skynet-bank-fe-flow (v0.8.9)
        3. drawio (vlatest)
        📋 ────────────────────────────────────────────────────────────
        [Codex] (2)
        📋 ────────────────────────────────────────────────────────────
        1. Filesystem (vlatest)
        2. gitlab-mcp
        """

    func testParsesMCPListTotalsAndGroups() throws {
        let summary = try XCTUnwrap(
            MCPOutputParser.parseMCPList(mcpListOutput)
        )

        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.ideGroups, ["Cursor": 3, "Codex": 2])
        XCTAssertEqual(summary.skynetBaseIDEs, ["Cursor"])
    }

    func testReturnsNilForUnrecognizedMCPListOutput() {
        XCTAssertNil(MCPOutputParser.parseMCPList("some unexpected error"))
        XCTAssertNil(MCPOutputParser.parseMCPList(""))
    }

    func testParsesInstalledSkillCount() {
        let output = """
            ✅ 167 个已安装的 Skill

            📋 ────────────────────────────────────────────────────────────
            1. a2ui (v2)
            2. ask-matt
            """

        XCTAssertEqual(MCPOutputParser.parseSkillCount(output), 167)
        XCTAssertNil(MCPOutputParser.parseSkillCount("✅ 0 个"))
        XCTAssertNil(MCPOutputParser.parseSkillCount("nope"))
    }

    func testMCPRowsReportMissingCoreMCPAsWarning() {
        let report = EnvironmentReport(
            cliPath: "/fake/bin/skynet",
            cliVersion: "2.7.29",
            nodeVersion: "v22.23.2",
            networkAvailable: true,
            mcpConfiguration: MCPConfiguration(
                mcpSummary: MCPOutputParser.parseMCPList(mcpListOutput),
                skillCount: 167
            )
        )

        let mcpRow = report.checks.first { $0.name == "MCP" }
        let skillRow = report.checks.first { $0.name == "Skills" }

        XCTAssertEqual(mcpRow?.status, .warning)
        XCTAssertEqual(mcpRow?.detail, "skynet-base MCP 未配置于 Codex")
        XCTAssertEqual(skillRow?.status, .passed)
        XCTAssertEqual(skillRow?.detail, "167 个已安装")
    }

    func testMCPRowsHiddenWhenProbesDidNotRun() {
        let report = EnvironmentReport(
            cliPath: nil,
            cliVersion: nil,
            nodeVersion: nil,
            networkAvailable: false
        )

        XCTAssertFalse(report.checks.contains { $0.name == "MCP" })
        XCTAssertFalse(report.checks.contains { $0.name == "Skills" })
    }

    func testMCPRowPassesWhenEveryIDEHasCoreMCP() {
        let report = EnvironmentReport(
            cliPath: "/fake/bin/skynet",
            cliVersion: "2.7.29",
            nodeVersion: "v22.23.2",
            networkAvailable: true,
            mcpConfiguration: MCPConfiguration(
                mcpSummary: MCPListSummary(
                    total: 4,
                    ideGroups: ["Cursor": 3, "Claude": 1],
                    skynetBaseIDEs: ["Cursor", "Claude"]
                ),
                skillCount: 3
            )
        )

        let mcpRow = report.checks.first { $0.name == "MCP" }

        XCTAssertEqual(mcpRow?.status, .passed)
        XCTAssertEqual(mcpRow?.detail, "4 个 · 2 个 IDE")
    }

    func testDoctorProbesMCPConfigurationThroughTheCLI() async {
        let runner = DoctorProbingRunner(results: [
            .succeeded(stdout: "v22.23.2\n"),               // node --version
            .succeeded(stdout: "/opt/homebrew/bin/skynet-base\n"), // skynet-base
            .succeeded(stdout: mcpListOutput + "\n"),       // mcp list
            .succeeded(stdout: "✅ 12 个已安装的 Skill\n"),  // skill list
        ])
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: runner
        )

        let report = await doctor.inspect(networkAvailable: true)

        XCTAssertEqual(
            report.mcpConfiguration?.mcpSummary?.skynetBaseIDEs,
            ["Cursor"]
        )
        XCTAssertEqual(report.mcpConfiguration?.skillCount, 12)
    }
}

private actor DoctorProbingRunner: CommandRunning {
    private var results: [CommandResult]

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        results.isEmpty ? .succeeded(stdout: "") : results.removeFirst()
    }
}

private extension CommandResult {
    static func succeeded(stdout: String) -> Self {
        CommandResult(stdout: stdout, stderr: "", exitCode: 0, timedOut: false)
    }
}

private struct DoctorStubLocator: CLIPathLocating {
    let url: URL?

    func locate() async throws -> URL {
        guard let url else {
            throw CLIPathError.notFound
        }
        return url
    }
}

private struct DoctorStubChecker: SkynetAuthChecking {
    private let version: String?

    init(version: String?) {
        self.version = version
    }

    func check(networkAvailable: Bool) async -> LoginState {
        .authenticated(email: nil)
    }

    func login(networkAvailable: Bool) async -> LoginActionResult {
        .alreadyAuthenticated(email: nil)
    }

    func version() async -> String? {
        version
    }
}
