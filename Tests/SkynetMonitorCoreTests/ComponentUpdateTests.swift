import Foundation
import XCTest
@testable import SkynetMonitorCore

final class ComponentUpdateTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    // MARK: - Platform client parsing

    func testDetailResponseParsesMainVersion() throws {
        let body = #"{"code":0,"msg":"success","data":{"skill_name":"fe-api-gen","main_version_number":"v10"}}"#

        XCTAssertEqual(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data(body.utf8)),
            "v10"
        )
    }

    func testDetailResponseWithoutDataIsNotAnError() throws {
        let body = #"{"code":0,"msg":"success","data":null}"#

        XCTAssertNil(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data(body.utf8))
        )
    }

    func testDetailResponseRejectsNonZeroCode() {
        let body = #"{"code":401,"msg":"unauthorized"}"#

        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data(body.utf8))
        ) { error in
            XCTAssertEqual(
                error as? HTTPSkynetPlatformClient.ClientError,
                .apiRejected
            )
        }
        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data("not json".utf8))
        ) { error in
            XCTAssertEqual(
                error as? HTTPSkynetPlatformClient.ClientError,
                .malformedResponse
            )
        }
    }

    func testSessionTokenParsing() {
        XCTAssertEqual(
            HTTPSkynetPlatformClient.parseSessionToken(
                from: Data(#"{"sessionId":"s","token":"abc"}"#.utf8)
            ),
            "abc"
        )
        XCTAssertNil(
            HTTPSkynetPlatformClient.parseSessionToken(
                from: Data(#"{"sessionId":"s"}"#.utf8)
            )
        )
    }

    func testListPageParsesVersionsAndTotals() throws {
        let body = """
        {"code":0,"data":{"total":1165,"page":1,"skills":[
          {"skill_name":"fe-api-gen","main_version_number":"v11"},
          {"skill_name":"no-version-skill"},
          {"skill_name":"bank-react-sdd-base-skill-v2","main_version_number":"v170"}
        ]}}
        """

        let result = try HTTPSkynetPlatformClient.parseListPage(
            from: Data(body.utf8)
        )

        XCTAssertEqual(result.total, 1165)
        XCTAssertEqual(result.returned, 3)
        XCTAssertEqual(
            result.versions,
            [
                "fe-api-gen": "v11",
                "bank-react-sdd-base-skill-v2": "v170",
            ]
        )
        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseListPage(from: Data("nope".utf8))
        )
        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseListPage(
                from: Data(#"{"code":401,"data":null}"#.utf8)
            )
        )
    }

    func testSkillCheckerPrefersBatchOverDetail() async throws {
        let lockURL = writeTemporaryFile(
            json: """
            {"fe-api-gen": {"version": "v10"}, "gone-skill": {"version": "v1"}}
            """
        )
        let client = StubPlatformClient(
            token: "session-token",
            latest: ["fe-api-gen": "v10", "gone-skill": "v2"],
            batch: ["fe-api-gen": "v11"]
        )
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(
                SkillUpdateReport(
                    totalChecked: 2,
                    updates: [
                        // Batch's v11 wins over detail's v10; the name the
                        // batch missed falls back to detail.
                        SkillUpdate(name: "fe-api-gen", installedVersion: "v10", latestVersion: "v11"),
                        SkillUpdate(name: "gone-skill", installedVersion: "v1", latestVersion: "v2"),
                    ]
                )
            )
        )
    }

    func testSkillCheckerFallsBackToDetailWhenBatchFails() async throws {
        let lockURL = writeTemporaryFile(
            json: #"{"fe-api-gen": {"version": "v10"}}"#
        )
        let client = StubPlatformClient(token: "session-token", latest: ["fe-api-gen": "v11"], batch: [:])
        client.batchFails = true
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(
                SkillUpdateReport(
                    totalChecked: 1,
                    updates: [
                        SkillUpdate(name: "fe-api-gen", installedVersion: "v10", latestVersion: "v11"),
                    ]
                )
            )
        )
    }

    // MARK: - SkillUpdateChecker

    func testSkillCheckerReportsOutdatedSkills() async throws {
        let lockURL = writeTemporaryFile(
            json: """
            {
              "fe-api-gen": {"version": "v10"},
              "bank-react-sdd-base-skill-v2": {"version": "v145"},
              "broken-version": {"version": "dev"}
            }
            """
        )
        let client = StubPlatformClient(
            token: "session-token",
            latest: [
                "fe-api-gen": "v10",
                "bank-react-sdd-base-skill-v2": "v170",
                "broken-version": "v999",
            ]
        )
        let checker = SkillUpdateChecker(
            lockURL: lockURL,
            client: client,
            maxConcurrent: 2
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(
                SkillUpdateReport(
                    totalChecked: 2,
                    updates: [
                        SkillUpdate(
                            name: "bank-react-sdd-base-skill-v2",
                            installedVersion: "v145",
                            latestVersion: "v170"
                        ),
                    ]
                )
            )
        )
    }

    func testSkillCheckerRequiresLoginWithoutSessionToken() async {
        let lockURL = writeTemporaryFile(json: #"{"a":{"version":"v1"}}"#)
        let checker = SkillUpdateChecker(
            lockURL: lockURL,
            client: StubPlatformClient(token: nil, latest: [:])
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .needsLogin)
    }

    func testSkillCheckerFailsWithoutLockFile() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let checker = SkillUpdateChecker(
            lockURL: missingURL,
            client: StubPlatformClient(token: "session-token", latest: [:])
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .failed)
    }

    func testSkillCheckerTreatsFetchErrorsAsUnknown() async throws {
        let lockURL = writeTemporaryFile(
            json: #"{"fe-api-gen": {"version": "v10"}, "gone-skill": {"version": "v1"}}"#
        )
        let client = StubPlatformClient(token: "session-token", latest: [:])
        client.failingSkills = ["fe-api-gen", "gone-skill"]
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(SkillUpdateReport(totalChecked: 2, updates: []))
        )
    }

    // MARK: - MCP plan and config parsing

    func testNpxPlanResolvesPinnedScopedPackage() {
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "/Users/x/.nvm/versions/node/v18.17.0/bin/npx",
                arguments: ["-y", "@shopee/banking-fe-mcp@0.2.27"]
            ),
            .npxPinned(package: "@shopee/banking-fe-mcp", pinnedVersion: "0.2.27")
        )
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "npx",
                arguments: ["-y", "-p", "@scope/tool", "--flag"]
            ),
            .npxUnpinned(package: "@scope/tool")
        )
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "npx",
                arguments: ["-y", "@zereight/mcp-gitlab"]
            ),
            .npxUnpinned(package: "@zereight/mcp-gitlab")
        )
    }

    func testBinaryPlansResolve() {
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "/Users/x/.nvm/versions/node/v18.17.0/bin/skynet-mcp",
                arguments: ["--mcp=skynet-base"]
            ),
            .globalBinary(
                binaryName: "skynet-mcp",
                binaryDirectory: "/Users/x/.nvm/versions/node/v18.17.0/bin"
            )
        )
        // Bare command names cannot be resolved without a PATH search.
        XCTAssertNil(
            McpServerPlan.plan(command: "banking-fe-mcp", arguments: [])
        )
        XCTAssertNil(
            McpServerPlan.plan(command: "npx", arguments: ["-y"])
        )
    }

    func testMcpConfigParsing() {
        let data = Data(
            """
            {"mcp":{"servers":{
              "zeta":{"type":"stdio","command":"npx","args":["-y","p@1.0"]},
              "alpha":{"type":"stdio","command":"/bin/alpha","args":[]},
              "broken":{"type":"stdio","args":[]}
            }}}
            """
                .utf8
        )

        let entries = McpConfigParser.parseServers(from: data)

        XCTAssertEqual(
            entries,
            [
                McpServerEntry(name: "alpha", command: "/bin/alpha", arguments: []),
                McpServerEntry(name: "zeta", command: "npx", arguments: ["-y", "p@1.0"]),
            ]
        )
        XCTAssertNil(McpConfigParser.parseServers(from: Data("nope".utf8)))
    }

    // MARK: - node_modules resolution

    func testNodeModulesReaderFindsOwningPackage() throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet-base")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet-base","version":"2.11.5",
         "bin":{"skynet-base":"dist/cli.js","skynet-mcp":"dist/mcp.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let package = NodeModulesPackageReader.package(
            owningBinary: "skynet-mcp",
            inBinaryDirectory: root.appendingPathComponent("bin").path
        )

        XCTAssertEqual(package?.name, "@shopee/skynet-base")
        XCTAssertEqual(package?.version, "2.11.5")
        XCTAssertNil(
            NodeModulesPackageReader.package(
                owningBinary: "unknown-binary",
                inBinaryDirectory: root.appendingPathComponent("bin").path
            )
        )
    }

    // MARK: - registry parsing

    func testRegistryResponseParsing() {
        XCTAssertEqual(
            HTTPNpmRegistryClient.parseLatestDocument(
                from: Data(#"{"name":"@shopee/skynet-cli","version":"2.8.0"}"#.utf8)
            ),
            "2.8.0"
        )
        XCTAssertEqual(
            HTTPNpmRegistryClient.parsePackumentDistTag(
                from: Data(#"{"name":"x","dist-tags":{"latest":"0.2.29","beta":"0.3.0"}}"#.utf8)
            ),
            "0.2.29"
        )
        XCTAssertNil(
            HTTPNpmRegistryClient.parseLatestDocument(from: Data("{}".utf8))
        )
    }

    func testNpmrcTokenParsing() {
        let contents = """
        registry=https://nexus.npt.seabank.io/repository/npm-bank/
        //nexus.npt.seabank.io/repository/npm-bank/:_authToken=token-a
        //npm.shopee.io/:_authToken="token-b"
        unrelated=line
        """

        let tokens = HTTPNpmRegistryClient.parseRegistryTokens(fromNpmrc: contents)

        XCTAssertEqual(
            tokens["nexus.npt.seabank.io"],
            "token-a"
        )
        XCTAssertEqual(tokens["npm.shopee.io"], "token-b")
        XCTAssertEqual(tokens.count, 2)
    }

    // MARK: - McpVersionChecker integration

    func testMcpCheckerProducesFindings() async throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet-base")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet-base","version":"2.11.5",
         "bin":{"skynet-mcp":"dist/mcp.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        // The configured path must exist on disk, or the checker treats it
        // as unresolvable and skips the node_modules lookup.
        let binURL = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: binURL,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: binURL.appendingPathComponent("skynet-mcp").path,
            contents: nil
        )

        let configURL = writeTemporaryFile(
            json: """
            {"mcp":{"servers":{
              "skynet-base":{"type":"stdio","command":"\(root.path)/bin/skynet-mcp","args":[]},
              "banking":{"type":"stdio","command":"npx","args":["-y","@shopee/banking-fe-mcp@0.2.27"]},
              "gitlab":{"type":"stdio","command":"npx","args":["-y","@zereight/mcp-gitlab"]}
            }}}
            """
        )
        let registry = StubRegistry(
            versions: [
                "@shopee/skynet-base": "2.12.2",
                "@shopee/banking-fe-mcp": "0.2.29",
            ]
        )
        let checker = McpVersionChecker(
            configURL: configURL,
            registry: registry,
            binarySearchPaths: []
        )

        let findings = await checker.checkVersions()

        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(
            findings.first { $0.serverName == "skynet-base" },
            McpVersionFinding(
                serverName: "skynet-base",
                packageName: "@shopee/skynet-base",
                installedVersion: "2.11.5",
                latestVersion: "2.12.2"
            )
        )
        XCTAssertEqual(
            findings.first { $0.serverName == "banking" }?.isUpgradable,
            true
        )
        XCTAssertEqual(
            findings.first { $0.serverName == "gitlab" }?.unpinned,
            true
        )
    }

    func testMcpCheckerFallsBackToSearchPathsForMissingBinary() async throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet.bank-fe-flow")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet.bank-fe-flow","version":"0.8.9",
         "bin":{"banking-fe-mcp":"dist/cli.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let alternateBin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: alternateBin,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: alternateBin.appendingPathComponent("banking-fe-mcp").path,
            contents: nil
        )

        let configURL = writeTemporaryFile(
            json: """
            {"mcp":{"servers":{
              "flow":{"type":"stdio","command":"banking-fe-mcp","args":[]}
            }}}
            """
        )
        let checker = McpVersionChecker(
            configURL: configURL,
            registry: StubRegistry(versions: ["@shopee/skynet.bank-fe-flow": "0.8.9"]),
            binarySearchPaths: [alternateBin.path]
        )

        let findings = await checker.checkVersions()

        XCTAssertEqual(
            findings,
            [
                McpVersionFinding(
                    serverName: "flow",
                    packageName: "@shopee/skynet.bank-fe-flow",
                    installedVersion: "0.8.9",
                    latestVersion: "0.8.9"
                ),
            ]
        )
    }

    // MARK: - MonitorStore wiring

    @MainActor
    func testCheckComponentUpdatesPublishesResults() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .completed(
            SkillUpdateReport(
                totalChecked: 56,
                updates: [
                    SkillUpdate(
                        name: "fe-api-gen",
                        installedVersion: "v10",
                        latestVersion: "v11"
                    ),
                ]
            )
        )
        let mcpChecker = MutableMcpVersionChecker()
        mcpChecker.findings = [
            McpVersionFinding(
                serverName: "skynet-base",
                packageName: "@shopee/skynet-base",
                installedVersion: "2.11.5",
                latestVersion: "2.12.2"
            ),
        ]
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker,
            mcpVersionChecker: mcpChecker
        )

        XCTAssertTrue(store.showsComponentUpdates)
        await store.checkComponentUpdates()

        XCTAssertEqual(store.skillUpdatePhase, .completed)
        XCTAssertEqual(store.skillUpdateReport?.updates.first?.name, "fe-api-gen")
        XCTAssertEqual(store.mcpVersionFindings.first?.serverName, "skynet-base")
        XCTAssertTrue(store.mcpVersionFindings.first?.isUpgradable ?? false)
    }

    @MainActor
    func testCheckComponentUpdatesPublishesNeedsLogin() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .needsLogin
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker
        )

        await store.checkComponentUpdates()

        XCTAssertEqual(store.skillUpdatePhase, .needsLogin)
        XCTAssertNil(store.skillUpdateReport)
    }

    @MainActor
    func testLoginRechecksComponentsWhenWaitingForLogin() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .needsLogin
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker
        )

        await store.checkComponentUpdates()
        XCTAssertEqual(store.skillUpdatePhase, .needsLogin)

        skillChecker.result = .completed(
            SkillUpdateReport(totalChecked: 5, updates: [])
        )
        await store.login()

        XCTAssertEqual(store.skillUpdatePhase, .completed)
        XCTAssertEqual(store.skillUpdateReport?.totalChecked, 5)
    }

    @MainActor
    func testStoreWithoutCheckersHidesComponentUpdates() async {
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil
        )

        XCTAssertFalse(store.showsComponentUpdates)
        XCTAssertFalse(store.showsUpdateCheck)
        await store.checkComponentUpdates()
        XCTAssertEqual(store.skillUpdatePhase, .idle)
    }

    // MARK: - diagnostics

    func testDiagnosticsIncludeComponentVersions() {
        let report = DiagnosticsComposer.compose(
            appVersion: "0.7.0",
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            skillUpdatePhase: .completed,
            skillUpdateReport: SkillUpdateReport(
                totalChecked: 56,
                updates: [
                    SkillUpdate(name: "a-skill", installedVersion: "v1", latestVersion: "v2"),
                    SkillUpdate(name: "b-skill", installedVersion: "v3", latestVersion: "v4"),
                ]
            ),
            mcpVersionFindings: [
                McpVersionFinding(
                    serverName: "skynet-base",
                    installedVersion: "2.11.5",
                    latestVersion: "2.12.2"
                ),
            ]
        )

        XCTAssertTrue(report.contains("组件版本：Skill 2/56 可升级（a-skill v1 → v2、b-skill v3 → v4）"))
        XCTAssertTrue(report.contains("组件版本：MCP 可升级 skynet-base 2.11.5 → 2.12.2"))
    }

    func testDiagnosticsAllCurrentAndNeedsLogin() {
        let current = DiagnosticsComposer.compose(
            appVersion: nil,
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            skillUpdatePhase: .completed,
            skillUpdateReport: SkillUpdateReport(totalChecked: 12, updates: [])
        )
        XCTAssertTrue(current.contains("组件版本：Skill 12 个均为最新"))

        let needsLogin = DiagnosticsComposer.compose(
            appVersion: nil,
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            skillUpdatePhase: .needsLogin
        )
        XCTAssertTrue(needsLogin.contains("组件版本：Skill 更新检测需登录后可用"))
    }

    // MARK: - helpers

    private func writeTemporaryFile(json: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try! json.write(to: url, atomically: true, encoding: .utf8)
        temporaryURLs.append(url)
        return url
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }
}

private final class StubPlatformClient: SkynetSkillVersionFetching, @unchecked Sendable {
    let token: String?
    var batch: [String: String]
    var latest: [String: String]
    var batchFails = false
    var failingSkills: Set<String> = []

    init(
        token: String?,
        latest: [String: String],
        batch: [String: String] = [:]
    ) {
        self.token = token
        self.latest = latest
        self.batch = batch
    }

    func sessionToken() async -> String? {
        token
    }

    func latestMainVersions() async throws -> [String: String] {
        if batchFails {
            throw HTTPSkynetPlatformClient.ClientError.apiRejected
        }
        return batch
    }

    func latestMainVersion(for skillName: String) async throws -> String? {
        if failingSkills.contains(skillName) {
            throw HTTPSkynetPlatformClient.ClientError.apiRejected
        }
        return latest[skillName]
    }
}

private final class StubRegistry: NpmRegistryLatestFetching, @unchecked Sendable {
    let versions: [String: String]

    init(versions: [String: String]) {
        self.versions = versions
    }

    func latestVersion(of package: String) async -> String? {
        versions[package]
    }
}

private final class MutableSkillUpdateChecker: SkillUpdateChecking, @unchecked Sendable {
    var result: SkillUpdateCheckResult = .failed

    func checkForUpdates() async -> SkillUpdateCheckResult {
        result
    }
}

private final class MutableMcpVersionChecker: McpVersionChecking, @unchecked Sendable {
    var findings: [McpVersionFinding] = []

    func checkVersions() async -> [McpVersionFinding] {
        findings
    }
}

private struct StubChecker: SkynetAuthChecking {
    func check(networkAvailable: Bool) async -> LoginState {
        .authenticated(email: nil)
    }

    func login(networkAvailable: Bool) async -> LoginActionResult {
        .alreadyAuthenticated(email: nil)
    }

    func version() async -> String? {
        nil
    }
}

@MainActor
private final class StubNetworkMonitor: NetworkMonitoring {
    var isAvailable = true

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) async {}

    func stop() {}
}

@MainActor
private final class StubNotifier: LoginNotifying {
    func requestAuthorization() async {}

    func authorizationStatus() async -> NotificationPermissionStatus {
        .authorized
    }

    func notifyLoginExpired() async {}

    func notifySessionExpiring(
        stage: SessionExpiryAdvisor.Stage,
        expiresAt: Date
    ) async {}

    func notifyServiceTokenInvalid(key: String, name: String) async {}

    func notifyCheckResult(_ state: LoginState) async {}

    func notifyLoginResult(_ result: LoginActionResult) async {}
}
