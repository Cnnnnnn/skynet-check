import Foundation

public enum EnvironmentCheckStatus: Equatable, Sendable {
    case passed
    case warning
    case failed
}

public struct EnvironmentCheck: Equatable, Sendable {
    public let name: String
    public let status: EnvironmentCheckStatus
    public let detail: String

    public init(
        name: String,
        status: EnvironmentCheckStatus,
        detail: String
    ) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct EnvironmentReport: Equatable, Sendable {
    public let cliPath: String?
    public let cliVersion: String?
    public let nodeVersion: String?
    public let networkAvailable: Bool
    public let latestCLIVersion: String?
    public let skynetBaseFound: Bool
    public let mcpConfiguration: MCPConfiguration?

    public init(
        cliPath: String?,
        cliVersion: String?,
        nodeVersion: String?,
        networkAvailable: Bool,
        latestCLIVersion: String? = nil,
        skynetBaseFound: Bool = true,
        mcpConfiguration: MCPConfiguration? = nil
    ) {
        self.cliPath = cliPath
        self.cliVersion = cliVersion
        self.nodeVersion = nodeVersion
        self.networkAvailable = networkAvailable
        self.latestCLIVersion = latestCLIVersion
        self.skynetBaseFound = skynetBaseFound
        self.mcpConfiguration = mcpConfiguration
    }

    public var checks: [EnvironmentCheck] {
        var allChecks = [
            EnvironmentCheck(
                name: "Skynet CLI",
                status: cliPath == nil ? .failed : .passed,
                detail: cliPath ?? MonitorText.Environment.cliMissingDetail
            ),
            EnvironmentCheck(
                name: "Node.js",
                status: nodeVersion == nil ? .failed : .passed,
                detail: nodeVersion ?? MonitorText.Environment.nodeMissingDetail
            ),
            EnvironmentCheck(
                name: "网络",
                status: networkAvailable ? .passed : .warning,
                detail: networkAvailable
                    ? MonitorText.Environment.networkAvailableDetail
                    : MonitorText.Environment.networkUnavailableDetail
            ),
            // skynet-base backs the key/ide-key commands; it is optional for
            // login monitoring, so a missing binary is a warning, not a
            // failure.
            EnvironmentCheck(
                name: "skynet-base",
                status: skynetBaseFound ? .passed : .warning,
                detail: skynetBaseFound
                    ? MonitorText.Environment.skynetBaseFoundDetail
                    : MonitorText.Environment.skynetBaseMissingDetail
            ),
        ]
        allChecks.append(contentsOf: mcpChecks)
        return allChecks
    }

    // MCP/Skills rows appear only when the probes ran (the CLI exists);
    // a missing CLI already surfaces through its own row.
    private var mcpChecks: [EnvironmentCheck] {
        guard let mcp = mcpConfiguration else {
            return []
        }

        var rows: [EnvironmentCheck] = []
        if let summary = mcp.mcpSummary {
            if summary.total == 0 {
                rows.append(
                    EnvironmentCheck(
                        name: "MCP",
                        status: .warning,
                        detail: MonitorText.Environment.mcpNoneConfigured
                    )
                )
            } else {
                let missingBase = summary.ideGroups.keys
                    .filter { !summary.skynetBaseIDEs.contains($0) }
                    .sorted()
                if missingBase.isEmpty {
                    rows.append(
                        EnvironmentCheck(
                            name: "MCP",
                            status: .passed,
                            detail: MonitorText.Environment.mcpSummary(
                                total: summary.total,
                                ideCount: summary.ideGroups.count
                            )
                        )
                    )
                } else {
                    rows.append(
                        EnvironmentCheck(
                            name: "MCP",
                            status: .warning,
                            detail: MonitorText.Environment.mcpMissingCore(
                                missingBase.joined(separator: "、")
                            )
                        )
                    )
                }
            }
        } else {
            rows.append(
                EnvironmentCheck(
                    name: "MCP",
                    status: .warning,
                    detail: MonitorText.Environment.mcpUnableToRead
                )
            )
        }

        if let skillCount = mcp.skillCount {
            rows.append(
                EnvironmentCheck(
                    name: "Skills",
                    status: skillCount == 0 ? .warning : .passed,
                    detail: skillCount == 0
                        ? MonitorText.Environment.skillNoneInstalled
                        : MonitorText.Environment.skillSummary(skillCount)
                )
            )
        } else {
            rows.append(
                EnvironmentCheck(
                    name: "Skills",
                    status: .warning,
                    detail: MonitorText.Environment.skillUnableToRead
                )
            )
        }
        return rows
    }
}

public actor EnvironmentDoctor {
    private let locator: any CLIPathLocating
    private let checker: any SkynetAuthChecking
    private let shellResolver: LoginShellResolver
    private let cliRunner: any CommandRunning
    private let cliVersionChecker: (any CLIVersionChecking)?

    public init(
        locator: any CLIPathLocating,
        checker: any SkynetAuthChecking,
        runner: any CommandRunning,
        cliVersionChecker: (any CLIVersionChecking)? = nil
    ) {
        self.locator = locator
        self.checker = checker
        self.shellResolver = LoginShellResolver(runner: runner)
        self.cliRunner = runner
        self.cliVersionChecker = cliVersionChecker
    }

    public func inspect(networkAvailable: Bool) async -> EnvironmentReport {
        let cliURL = try? await locator.locate()
        let nodeVersion = await discoverNodeVersion()
        return EnvironmentReport(
            cliPath: cliURL?.path,
            cliVersion: await checker.version(),
            nodeVersion: nodeVersion,
            networkAvailable: networkAvailable,
            latestCLIVersion: await fetchLatestCLIVersion(),
            skynetBaseFound: await isSkynetBaseInstalled(),
            mcpConfiguration: await probeMCPConfiguration(cliURL: cliURL)
        )
    }

    private func probeMCPConfiguration(cliURL: URL?) async -> MCPConfiguration? {
        guard let cliURL else {
            return nil
        }
        async let mcpOutput = runCLI(cliURL, ["mcp", "list"])
        async let skillOutput = runCLI(cliURL, ["skill", "list"])
        return MCPConfiguration(
            mcpSummary: await mcpOutput.flatMap(MCPOutputParser.parseMCPList),
            skillCount: await skillOutput.flatMap(MCPOutputParser.parseSkillCount)
        )
    }

    private func runCLI(_ cliURL: URL, _ arguments: [String]) async -> String? {
        let result = await cliRunner.run(
            executableURL: cliURL,
            arguments: arguments,
            environment: CLIExecutionEnvironment.base(for: cliURL),
            timeout: .seconds(8)
        )
        guard !result.timedOut, result.exitCode == 0 else {
            return nil
        }
        return result.stdout
    }

    // skynet spawns the skynet-base binary from the user's shell PATH, so
    // presence is probed in a login shell rather than the app's own PATH.
    private func isSkynetBaseInstalled() async -> Bool {
        await shellResolver.resolve(command: "command -v skynet-base") != nil
    }

    private func fetchLatestCLIVersion() async -> String? {
        guard let cliVersionChecker else {
            return nil
        }
        do {
            let latest = try await cliVersionChecker.fetchLatest()
            MonitorLog.cli.info("registry reports latest skynet CLI \(latest, privacy: .public)")
            return latest
        } catch {
            // Registry reachability is best-effort; diagnostics still work.
            MonitorLog.cli.debug("failed to fetch latest CLI version")
            return nil
        }
    }

    private func discoverNodeVersion() async -> String? {
        guard
            let output = await shellResolver.resolve(command: "node --version")
        else {
            return nil
        }
        let version = output
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return version?.isEmpty == false ? version : nil
    }
}
