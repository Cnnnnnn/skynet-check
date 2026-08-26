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

    func testParsesMCPListFromJSON() throws {
        let summary = try XCTUnwrap(
            MCPOutputParser.parseMCPList(fromJSON: Data(mcpListJSON.utf8))
        )

        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.ideGroups, ["Cursor": 3, "Codex": 2])
        XCTAssertEqual(summary.skynetBaseIDEs, ["Cursor"])
        XCTAssertNil(summary.ideGroups["Claude"])
    }

    func testReturnsNilForUnrecognizedMCPListJSON() {
        XCTAssertNil(
            MCPOutputParser.parseMCPList(fromJSON: Data("[]".utf8))
        )
        XCTAssertNil(
            MCPOutputParser.parseMCPList(fromJSON: Data("not json".utf8))
        )
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

    func testParsesInstalledSkillsFromJSON() {
        let json = #"""
            [
              {"name": "a2ui", "version": "v2"},
              {"name": "ask-matt", "version": ""}
            ]
            """#

        let installed = SkillInventoryParser.parseInstalledSkills(
            fromJSON: Data(json.utf8)
        )

        XCTAssertEqual(
            installed,
            [
                InstalledSkill(name: "a2ui", version: "v2"),
                InstalledSkill(name: "ask-matt", version: ""),
            ]
        )
        XCTAssertNil(
            SkillInventoryParser.parseInstalledSkills(fromJSON: Data("not json".utf8))
        )
    }

    func testParsesLockBaselineFromJSON() {
        let json = #"""
            {"fe-api-gen": {"version": "v10"}, "skill-jira": {"version": "v6"}}
            """#

        let baseline = SkillInventoryParser.parseLockBaseline(
            fromJSON: Data(json.utf8)
        )

        XCTAssertEqual(
            baseline,
            ["fe-api-gen": "v10", "skill-jira": "v6"]
        )
        XCTAssertNil(
            SkillInventoryParser.parseLockBaseline(fromJSON: Data("[]".utf8))
        )
    }

    func testEvaluatorFlagsOutdatedMissingAndUnknownSkills() {
        let outdated = SkillUpdateEvaluator.outdatedSkills(
            installed: [
                InstalledSkill(name: "current-skill", version: "v10"),
                InstalledSkill(name: "older-skill", version: "v9"),
                InstalledSkill(name: "no-version-skill", version: ""),
            ],
            baseline: [
                "current-skill": "v10",
                "older-skill": "v11",
                "missing-skill": "v3",
                "no-version-skill": "v2",
                "unparsable-skill": "beta",
            ]
        )

        XCTAssertEqual(
            outdated,
            [
                OutdatedSkill(name: "missing-skill", installedVersion: nil, expectedVersion: "v3"),
                OutdatedSkill(name: "no-version-skill", installedVersion: nil, expectedVersion: "v2"),
                OutdatedSkill(name: "older-skill", installedVersion: "v9", expectedVersion: "v11"),
            ]
        )
    }

    func testSkillRowWarnsWhenOutdatedAgainstBaseline() {
        let report = EnvironmentReport(
            cliPath: "/fake/bin/skynet",
            cliVersion: "2.7.29",
            nodeVersion: "v22.23.2",
            networkAvailable: true,
            mcpConfiguration: MCPConfiguration(
                mcpSummary: nil,
                skillCount: 167,
                outdatedSkills: [
                    OutdatedSkill(name: "older-skill", installedVersion: "v9", expectedVersion: "v11"),
                ]
            )
        )

        let skillRow = report.checks.first { $0.name == "Skills" }

        XCTAssertEqual(skillRow?.status, .warning)
        XCTAssertEqual(skillRow?.detail, "167 个已安装，1 个落后于团队 lock")
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

    func testDoctorProbesMCPConfigurationThroughTheCLI() async throws {
        let lockURL = try writeTemporaryLock(
            baseline: ["fe-api-gen": "v10", "fe-td-generator": "v11"]
        )
        let runner = RoutingDoctorRunner(
            mcpListJSON: mcpListJSON,
            mcpListOutput: mcpListOutput,
            skillListOutput: skillListJSON
        )
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: runner,
            skillLockURL: lockURL
        )

        let report = await doctor.inspect(networkAvailable: true)

        XCTAssertEqual(
            report.mcpConfiguration?.mcpSummary?.skynetBaseIDEs,
            ["Cursor"]
        )
        XCTAssertEqual(
            report.mcpConfiguration?.mcpSummary?.ideGroups,
            ["Cursor": 3, "Codex": 2]
        )
        XCTAssertEqual(report.mcpConfiguration?.skillCount, 3)
        XCTAssertEqual(
            report.mcpConfiguration?.outdatedSkills,
            [
                OutdatedSkill(name: "fe-td-generator", installedVersion: nil, expectedVersion: "v11"),
            ]
        )
    }

    func testDoctorFallsBackToTextMCPListWhenJSONUnavailable() async throws {
        let runner = RoutingDoctorRunner(
            mcpListJSON: nil,
            mcpListOutput: mcpListOutput,
            skillListOutput: skillListJSON
        )
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: runner,
            skillLockURL: nil
        )

        let report = await doctor.inspect(networkAvailable: true)

        XCTAssertEqual(
            report.mcpConfiguration?.mcpSummary?.total,
            5
        )
        XCTAssertEqual(
            report.mcpConfiguration?.mcpSummary?.skynetBaseIDEs,
            ["Cursor"]
        )
    }

    private var mcpListJSON: String {
        #"""
        {
          "Cursor": [
            {"name": "skynet-base", "version": "v2.11.5"},
            {"name": "skynet-bank-fe-flow", "version": "v0.8.9"},
            {"name": "drawio", "version": "vlatest"}
          ],
          "Claude": [],
          "Codex": [
            {"name": "Filesystem", "version": "vlatest"},
            {"name": "gitlab-mcp", "version": ""}
          ]
        }
        """#
    }

    private var skillListJSON: String {
        #"""
        [
          {"name": "fe-api-gen", "version": "v10"},
          {"name": "older-skill", "version": "v9"},
          {"name": "a2ui", "version": "v2"}
        ]
        """#
    }

    private func writeTemporaryLock(baseline: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-lock-\(UUID().uuidString).json")
        let payload = Dictionary(
            uniqueKeysWithValues: baseline.map { name, version in
                (name, ["version": version])
            }
        )
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

// Probes run concurrently inside EnvironmentDoctor, so this runner routes
// by command instead of consuming an ordered queue.
private actor RoutingDoctorRunner: CommandRunning {
    private let mcpListJSON: String?
    private let mcpListOutput: String
    private let skillListOutput: String

    init(
        mcpListJSON: String?,
        mcpListOutput: String,
        skillListOutput: String
    ) {
        self.mcpListJSON = mcpListJSON
        self.mcpListOutput = mcpListOutput
        self.skillListOutput = skillListOutput
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        if arguments.contains("node") && arguments.contains("--version") {
            return .succeeded(stdout: "v22.23.2\n")
        }
        if arguments.contains("command") && arguments.contains("-v") {
            return .succeeded(stdout: "/opt/homebrew/bin/skynet-base\n")
        }
        if arguments.contains("mcp") {
            let wantsJSON = arguments.contains("-j") || arguments.contains("--json")
            if wantsJSON {
                guard let mcpListJSON else {
                    return .failed()
                }
                return .succeeded(stdout: mcpListJSON + "\n")
            }
            return .succeeded(stdout: mcpListOutput + "\n")
        }
        if arguments.contains("skill") {
            return .succeeded(stdout: skillListOutput + "\n")
        }
        return .failed()
    }
}

private extension CommandResult {
    static func succeeded(stdout: String) -> Self {
        CommandResult(stdout: stdout, stderr: "", exitCode: 0, timedOut: false)
    }

    static func failed() -> Self {
        CommandResult(stdout: "", stderr: "", exitCode: 1, timedOut: false)
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
