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

public struct McpVersionFinding: Codable, Equatable, Sendable {
    public let serverName: String
    public let packageName: String?
    public let installedVersion: String?
    public let latestVersion: String?
    public let unpinned: Bool
    // True when the installed version is a pin written in the config file
    // (npx -y pkg@version): upgrading means editing that pin, not npm.
    public let isNPXPinned: Bool
    // Which IDE's MCP config the entry came from ("ZCode" / "Cursor") —
    // the same package may be wired into both at different versions.
    public let configSource: String

    public init(
        serverName: String,
        packageName: String? = nil,
        installedVersion: String? = nil,
        latestVersion: String? = nil,
        unpinned: Bool = false,
        isNPXPinned: Bool = false,
        configSource: String = "ZCode"
    ) {
        self.serverName = serverName
        self.packageName = packageName
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.unpinned = unpinned
        self.isNPXPinned = isNPXPinned
        self.configSource = configSource
    }

    public var isUpgradable: Bool {
        guard let installedVersion,
              let latestVersion,
              let installed = SemanticVersion(installedVersion),
              let latest = SemanticVersion(latestVersion)
        else {
            return false
        }
        return latest > installed
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

    // Reads the ZCode MCP config shape:
    // {"mcp":{"servers":{"<name>":{"type":"stdio","command":…,"args":[…]}}}}
    public static func parseServers(from data: Data) -> [McpServerEntry]? {
        struct Config: Decodable {
            let mcp: MCP?
            struct MCP: Decodable {
                let servers: [String: Server]?
            }
        }

        guard let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        return entries(from: config.mcp?.servers ?? [:])
    }

    // Cursor keeps its MCP servers in ~/.cursor/mcp.json under
    // {"mcpServers":{"<name>":{"command":…,"args":[…]}}} — same fields,
    // different nesting.
    public static func parseCursorServers(from data: Data) -> [McpServerEntry]? {
        struct Config: Decodable {
            let mcpServers: [String: Server]?
        }

        guard let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        return entries(from: config.mcpServers ?? [:])
    }
}

public protocol McpVersionChecking: Sendable {
    func checkVersions() async -> [McpVersionFinding]
}

// Detection only: the findings name the installed and latest versions; the
// upgrade itself is the CLI's `skynet update tools` / npm's job.
public actor McpVersionChecker: McpVersionChecking {
    private let configURL: URL
    private let cursorConfigURL: URL?
    private let registry: any NpmRegistryLatestFetching
    private let binarySearchPaths: [String]
    private let fileManager: FileManager

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode/cli/config.json"),
        cursorConfigURL: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json"),
        registry: any NpmRegistryLatestFetching,
        binarySearchPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.cursorConfigURL = cursorConfigURL
        self.registry = registry
        self.fileManager = fileManager
        self.binarySearchPaths = binarySearchPaths ?? Self.defaultBinarySearchPaths()
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
        // Both IDE configs are read; identical server names stay separate
        // findings because each config can pin a different version.
        var sourcedEntries: [(entry: McpServerEntry, source: String)] = []
        if let data = try? Data(contentsOf: configURL),
           let entries = McpConfigParser.parseServers(from: data)
        {
            sourcedEntries.append(
                contentsOf: entries.map { ($0, "ZCode") }
            )
        }
        if let cursorConfigURL,
           let data = try? Data(contentsOf: cursorConfigURL),
           let entries = McpConfigParser.parseCursorServers(from: data)
        {
            sourcedEntries.append(
                contentsOf: entries.map { ($0, "Cursor") }
            )
        }
        guard !sourcedEntries.isEmpty else {
            return []
        }

        return await withTaskGroup(of: McpVersionFinding.self) { group in
            for sourced in sourcedEntries {
                group.addTask {
                    await self.finding(
                        for: sourced.entry,
                        source: sourced.source
                    )
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
                configSource: source
            )

        case let .npxPinned(package, pinnedVersion):
            return McpVersionFinding(
                serverName: entry.name,
                packageName: package,
                installedVersion: pinnedVersion,
                latestVersion: await registry.latestVersion(of: package),
                isNPXPinned: true,
                configSource: source
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
        var directory = (command as NSString).deletingLastPathComponent
        let binaryName = (command as NSString).lastPathComponent
        if !fileManager.fileExists(atPath: command) {
            let candidate = binarySearchPaths
                .map { ($0 as NSString).appendingPathComponent(binaryName) }
                .first { fileManager.fileExists(atPath: $0) }
            guard let resolved = candidate else {
                return McpVersionFinding(
                    serverName: entry.name,
                    configSource: source
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
                configSource: source
            )
        }
        return McpVersionFinding(
            serverName: entry.name,
            packageName: package.name,
            installedVersion: package.version,
            latestVersion: await registry.latestVersion(of: package.name),
            configSource: source
        )
    }
}
