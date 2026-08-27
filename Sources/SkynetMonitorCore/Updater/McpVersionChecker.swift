import Foundation

public struct McpServerEntry: Equatable, Sendable {
    public let name: String
    public let command: String
    public let arguments: [String]

    public init(name: String, command: String, arguments: [String]) {
        self.name = name
        self.command = command
        self.arguments = arguments
    }
}

public enum McpServerPlan: Equatable, Sendable {
    case npxPinned(package: String, pinnedVersion: String)
    case npxUnpinned(package: String)
    case globalBinary(binaryName: String, binaryDirectory: String)

    // How the entry is invoked says where its version lives: an npx pin is
    // written in the config line itself, a resolved binary path points at
    // the sibling node_modules tree, and a bare command name cannot be
    // resolved without a PATH search the app does not do.
    public static func plan(command: String, arguments: [String]) -> McpServerPlan? {
        let executable = (command as NSString).lastPathComponent
        if executable == "npx" {
            guard let spec = firstPackageSpec(in: arguments) else {
                return nil
            }
            // A scoped package's leading "@" is not a version pin; only a
            // separator after position zero splits package@version.
            if let separator = spec.lastIndex(of: "@"), separator > spec.startIndex {
                let package = String(spec[..<separator])
                let version = String(spec[spec.index(after: separator)...])
                if !version.isEmpty {
                    return .npxPinned(package: package, pinnedVersion: version)
                }
            }
            return .npxUnpinned(package: spec)
        }
        guard command.contains("/") else {
            return nil
        }
        let directory = (command as NSString).deletingLastPathComponent
        return .globalBinary(binaryName: executable, binaryDirectory: directory)
    }

    // npx arguments are flags plus one package spec; "-p <pkg>" names the
    // package explicitly when present.
    private static func firstPackageSpec(in arguments: [String]) -> String? {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "-p" || argument == "--package" {
                if let next = iterator.next(), !next.isEmpty {
                    return next
                }
                continue
            }
            if argument.hasPrefix("-") {
                continue
            }
            return argument.isEmpty ? nil : argument
        }
        return nil
    }
}

// ".../.nvm/versions/node/v22.23.2/bin/skynet-mcp" → "v22.23.2"
public enum NvmPaths {
    public static func nodeVersion(inPath path: String) -> String? {
        let marker = "/.nvm/versions/node/"
        guard let range = path.range(of: marker) else {
            return nil
        }
        let version = path[range.upperBound...].prefix(while: { $0 != "/" })
        return version.isEmpty ? nil : String(version)
    }
}

public struct McpVersionFinding: Codable, Equatable, Sendable {
    public let serverName: String
    public let packageName: String?
    public let installedVersion: String?
    public let latestVersion: String?
    public let unpinned: Bool
    // True when the installed version is a pin written in the config file
    // (npx -y pkg@version): upgrading means editing that pin, not npm.
    public let isNPXPinned: Bool
    // Which IDE's MCP config the entry came from ("Cursor" / "Codex") —
    // the same package may be wired into both at different versions.
    public let configSource: String
    // command from the IDE config; Cursor often pins an absolute nvm path
    // that differs from the shell's active `nvm use`.
    public let configuredCommand: String?
    // Absolute command path in the config that is not on disk (stale nvm
    // pin). Version may still come from a PATH fallback elsewhere.
    public let configuredBinaryMissing: Bool
    // nvm version baked into configuredCommand, when absolute.
    public let configuredNvmNode: String?
    // Login-shell `command -v node` nvm version when it differs from
    // configuredNvmNode — upgrading with a bare npm then misses the IDE.
    public let pathNvmNode: String?

    public init(
        serverName: String,
        packageName: String? = nil,
        installedVersion: String? = nil,
        latestVersion: String? = nil,
        unpinned: Bool = false,
        isNPXPinned: Bool = false,
        configSource: String = "Cursor",
        configuredCommand: String? = nil,
        configuredBinaryMissing: Bool = false,
        configuredNvmNode: String? = nil,
        pathNvmNode: String? = nil
    ) {
        self.serverName = serverName
        self.packageName = packageName
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.unpinned = unpinned
        self.isNPXPinned = isNPXPinned
        self.configSource = configSource
        self.configuredCommand = configuredCommand
        self.configuredBinaryMissing = configuredBinaryMissing
        let configuredNode = configuredNvmNode
            ?? configuredCommand.flatMap(NvmPaths.nodeVersion(inPath:))
        self.configuredNvmNode = configuredNode
        self.pathNvmNode = (configuredNode != nil && pathNvmNode != configuredNode)
            ? pathNvmNode
            : nil
    }

    public var hasNvmNodeMismatch: Bool {
        pathNvmNode != nil
    }

    // Higher first on the component card: upgrades, then nvm mismatches.
    public var displayAttentionRank: Int {
        (isUpgradable ? 2 : 0) + (hasNvmNodeMismatch ? 1 : 0)
    }

    // Treat a missing configured binary as needing an upgrade even when a
    // PATH fallback happens to already match latest — the IDE won't start it.
    public var isUpgradable: Bool {
        if configuredBinaryMissing {
            return latestVersion != nil || packageName != nil
        }
        guard let installedVersion,
              let latestVersion,
              let installed = SemanticVersion(installedVersion),
              let latest = SemanticVersion(latestVersion)
        else {
            return false
        }
        return latest > installed
    }

    func annotating(pathNvmNode: String?) -> McpVersionFinding {
        McpVersionFinding(
            serverName: serverName,
            packageName: packageName,
            installedVersion: installedVersion,
            latestVersion: latestVersion,
            unpinned: unpinned,
            isNPXPinned: isNPXPinned,
            configSource: configSource,
            configuredCommand: configuredCommand,
            configuredBinaryMissing: configuredBinaryMissing,
            configuredNvmNode: configuredNvmNode,
            pathNvmNode: pathNvmNode
        )
    }

    // Stable: upgradable / nvm-mismatch rows float up; ties keep input order.
    public static func sortedForDisplay(
        _ findings: [McpVersionFinding]
    ) -> [McpVersionFinding] {
        findings.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.displayAttentionRank
                let right = rhs.element.displayAttentionRank
                if left != right {
                    return left > right
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

public enum McpConfigParser {
    private struct Server: Decodable {
        let command: String?
        let args: [String]?
    }

    private static func entries(
        from servers: [String: Server]
    ) -> [McpServerEntry] {
        servers
            .compactMap { name, server -> McpServerEntry? in
                guard let command = server.command, !command.isEmpty else {
                    return nil
                }
                return McpServerEntry(
                    name: name,
                    command: command,
                    arguments: server.args ?? []
                )
            }
            .sorted { $0.name < $1.name }
    }

    // Cursor keeps its MCP servers in ~/.cursor/mcp.json under
    // {"mcpServers":{"<name>":{"command":…,"args":[…]}}}.
    public static func parseCursorServers(from data: Data) -> [McpServerEntry]? {
        struct Config: Decodable {
            let mcpServers: [String: Server]?
        }

        guard let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        return entries(from: config.mcpServers ?? [:])
    }

    // Codex stores MCP servers in ~/.codex/config.toml as
    // [mcp_servers.<name>] tables with command / args. No TOML dependency:
    // only the fields the version checker needs are scraped.
    public static func parseCodexServers(from data: Data) -> [McpServerEntry]? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parseCodexServers(from: text)
    }

    public static func parseCodexServers(from text: String) -> [McpServerEntry] {
        var entries: [McpServerEntry] = []
        var currentName: String?
        var command: String?
        var arguments: [String] = []
        var enabled = true
        var collectingArgs = false
        var argsBuffer = ""

        func flush() {
            defer {
                currentName = nil
                command = nil
                arguments = []
                enabled = true
                collectingArgs = false
                argsBuffer = ""
            }
            guard let name = currentName,
                  enabled,
                  let command,
                  !command.isEmpty
            else {
                return
            }
            entries.append(
                McpServerEntry(name: name, command: command, arguments: arguments)
            )
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if collectingArgs {
                argsBuffer += " " + line
                if line.contains("]") {
                    arguments = Self.tomlStringArray(argsBuffer)
                    collectingArgs = false
                    argsBuffer = ""
                }
                continue
            }
            if line.hasPrefix("[") {
                flush()
                currentName = Self.codexServerName(fromHeader: line)
                continue
            }
            guard currentName != nil else {
                continue
            }
            if line.hasPrefix("command") {
                if let value = Self.tomlStringValue(line) {
                    command = value
                }
            } else if line.hasPrefix("args") {
                if line.contains("]") {
                    arguments = Self.tomlStringArray(line)
                } else {
                    collectingArgs = true
                    argsBuffer = line
                }
            } else if line.hasPrefix("enabled") {
                enabled = !line.contains("false")
            }
        }
        flush()
        return entries.sorted { $0.name < $1.name }
    }

    // [mcp_servers.name] / [mcp_servers."Name With Spaces"] — subtables
    // like [mcp_servers.name.env] are ignored (key contains an extra ".").
    private static func codexServerName(fromHeader line: String) -> String? {
        guard line.hasPrefix("[mcp_servers."), line.hasSuffix("]") else {
            return nil
        }
        let inner = String(line.dropFirst("[mcp_servers.".count).dropLast())
        let name: String
        if inner.hasPrefix("\""), inner.hasSuffix("\""), inner.count >= 2 {
            name = String(inner.dropFirst().dropLast())
        } else {
            name = inner
        }
        if name.isEmpty || name.contains(".") {
            return nil
        }
        return name
    }

    private static func tomlStringValue(_ line: String) -> String? {
        guard let start = line.firstIndex(of: "\"") else {
            return nil
        }
        let after = line.index(after: start)
        guard let end = line[after...].firstIndex(of: "\"") else {
            return nil
        }
        return String(line[after..<end])
    }

    private static func tomlStringArray(_ text: String) -> [String] {
        var values: [String] = []
        var remaining = text[...]
        while let start = remaining.firstIndex(of: "\"") {
            let after = remaining.index(after: start)
            guard let end = remaining[after...].firstIndex(of: "\"") else {
                break
            }
            values.append(String(remaining[after..<end]))
            remaining = remaining[remaining.index(after: end)...]
        }
        return values
    }
}

public protocol McpVersionChecking: Sendable {
    func checkVersions() async -> [McpVersionFinding]
}

// Detection only: the findings name the installed and latest versions; the
// upgrade itself is pasteable Terminal text (see CLIInstallGuide).
public actor McpVersionChecker: McpVersionChecking {
    private let cursorConfigURL: URL?
    private let codexConfigURL: URL?
    private let registry: any NpmRegistryLatestFetching
    private let binarySearchPaths: [String]
    private let fileManager: FileManager
    private let runner: (any CommandRunning)?

    public init(
        cursorConfigURL: URL? = SkynetEndpoints.cursorConfigURL,
        codexConfigURL: URL? = SkynetEndpoints.codexConfigURL,
        registry: any NpmRegistryLatestFetching,
        binarySearchPaths: [String]? = nil,
        fileManager: FileManager = .default,
        runner: (any CommandRunning)? = nil
    ) {
        self.cursorConfigURL = cursorConfigURL
        self.codexConfigURL = codexConfigURL
        self.registry = registry
        self.fileManager = fileManager
        self.binarySearchPaths = binarySearchPaths ?? Self.defaultBinarySearchPaths()
        self.runner = runner
    }

    // MCP configs often reference binaries through bare names or nvm paths;
    // the nvm bin directories are enumerated up front so bare names can be
    // resolved the same way a login shell would find them.
    private static func defaultBinarySearchPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmVersions = URL(fileURLWithPath: home)
            .appendingPathComponent(".nvm/versions/node")
        var paths = ["/usr/local/bin", "/opt/homebrew/bin"]
        if let versions = try? FileManager.default.contentsOfDirectory(
            atPath: nvmVersions.path
        ) {
            paths.append(
                contentsOf: versions
                    .sorted()
                    .reversed()
                    .map { nvmVersions.appendingPathComponent($0).appendingPathComponent("bin").path }
            )
        }
        return paths
    }

    public func checkVersions() async -> [McpVersionFinding] {
        // Cursor + Codex only. Identical server names stay separate findings
        // because each config can pin a different version. A file that exists
        // but cannot be read or parsed is logged — "no servers" and
        // "unreadable config" must stay distinguishable.
        var sourcedEntries: [(entry: McpServerEntry, source: String)] = []
        appendCursorEntries(into: &sourcedEntries)
        appendCodexEntries(into: &sourcedEntries)
        guard !sourcedEntries.isEmpty else {
            return []
        }

        let pathNvmNode = await resolvePathNvmNode()

        return await withTaskGroup(of: McpVersionFinding.self) { group in
            for sourced in sourcedEntries {
                group.addTask {
                    let finding = await self.finding(
                        for: sourced.entry,
                        source: sourced.source
                    )
                    return finding.annotating(pathNvmNode: pathNvmNode)
                }
            }
            var findings: [McpVersionFinding] = []
            for await finding in group {
                findings.append(finding)
            }
            return findings.sorted {
                ($0.serverName, $0.configSource)
                    < ($1.serverName, $1.configSource)
            }
        }
    }

    // Login-shell node: Finder-launched apps lack nvm on PATH.
    private func resolvePathNvmNode() async -> String? {
        guard let runner else {
            return nil
        }
        let path = await LoginShellResolver(runner: runner)
            .resolve(command: "command -v node")
        return path.flatMap(NvmPaths.nodeVersion(inPath:))
    }

    private func appendCursorEntries(
        into sourcedEntries: inout [(entry: McpServerEntry, source: String)]
    ) {
        guard let cursorConfigURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: cursorConfigURL.path) else {
            return
        }
        if let data = try? Data(contentsOf: cursorConfigURL),
           let entries = McpConfigParser.parseCursorServers(from: data)
        {
            sourcedEntries.append(
                contentsOf: entries.map { ($0, "Cursor") }
            )
        } else {
            let path = cursorConfigURL.path
            MonitorLog.store.error(
                "cursor MCP config exists at \(path, privacy: .public) but could not be read or parsed"
            )
        }
    }

    private func appendCodexEntries(
        into sourcedEntries: inout [(entry: McpServerEntry, source: String)]
    ) {
        guard let codexConfigURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: codexConfigURL.path) else {
            return
        }
        if let data = try? Data(contentsOf: codexConfigURL),
           let entries = McpConfigParser.parseCodexServers(from: data)
        {
            sourcedEntries.append(
                contentsOf: entries.map { ($0, "Codex") }
            )
        } else {
            let path = codexConfigURL.path
            MonitorLog.store.error(
                "codex MCP config exists at \(path, privacy: .public) but could not be read or parsed"
            )
        }
    }

    private func finding(
        for entry: McpServerEntry,
        source: String
    ) async -> McpVersionFinding {
        guard let plan = McpServerPlan.plan(
            command: entry.command,
            arguments: entry.arguments
        ) else {
            return await resolvedFinding(
                for: entry,
                command: entry.command,
                source: source
            )
        }

        switch plan {
        case let .npxUnpinned(package):
            // An unpinned npx entry resolves fresh on every launch; there is
            // nothing installed to fall behind.
            return McpVersionFinding(
                serverName: entry.name,
                packageName: package,
                unpinned: true,
                configSource: source,
                configuredCommand: entry.command
            )

        case let .npxPinned(package, pinnedVersion):
            return McpVersionFinding(
                serverName: entry.name,
                packageName: package,
                installedVersion: pinnedVersion,
                latestVersion: await registry.latestVersion(of: package),
                isNPXPinned: true,
                configSource: source,
                configuredCommand: entry.command
            )

        case let .globalBinary(binaryName, binaryDirectory):
            return await resolvedFinding(
                for: entry,
                command: binaryDirectory + "/" + binaryName,
                source: source
            )
        }
    }

    // Global binaries need the package manifest for a version; when the
    // configured path does not exist (bare command name, moved nvm), the
    // nvm search paths get a chance to locate the same binary elsewhere.
    private func resolvedFinding(
        for entry: McpServerEntry,
        command: String,
        source: String
    ) async -> McpVersionFinding {
        let binaryMissing = entry.command.contains("/")
            && !fileManager.fileExists(atPath: entry.command)
        var directory = (command as NSString).deletingLastPathComponent
        let binaryName = (command as NSString).lastPathComponent
        if !fileManager.fileExists(atPath: command) {
            let candidate = binarySearchPaths
                .map { ($0 as NSString).appendingPathComponent(binaryName) }
                .first { fileManager.fileExists(atPath: $0) }
            guard let resolved = candidate else {
                return McpVersionFinding(
                    serverName: entry.name,
                    configSource: source,
                    configuredCommand: entry.command,
                    configuredBinaryMissing: binaryMissing
                )
            }
            directory = (resolved as NSString).deletingLastPathComponent
        }
        guard let package = NodeModulesPackageReader.package(
            owningBinary: binaryName,
            inBinaryDirectory: directory,
            fileManager: fileManager
        ) else {
            return McpVersionFinding(
                serverName: entry.name,
                configSource: source,
                configuredCommand: entry.command,
                configuredBinaryMissing: binaryMissing
            )
        }
        return McpVersionFinding(
            serverName: entry.name,
            packageName: package.name,
            installedVersion: package.version,
            latestVersion: await registry.latestVersion(of: package.name),
            configSource: source,
            configuredCommand: entry.command,
            configuredBinaryMissing: binaryMissing
        )
    }
}
