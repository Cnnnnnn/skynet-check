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

public struct McpVersionFinding: Equatable, Sendable {
    public let serverName: String
    public let packageName: String?
    public let installedVersion: String?
    public let latestVersion: String?
    public let unpinned: Bool

    public init(
        serverName: String,
        packageName: String? = nil,
        installedVersion: String? = nil,
        latestVersion: String? = nil,
        unpinned: Bool = false
    ) {
        self.serverName = serverName
        self.packageName = packageName
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.unpinned = unpinned
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
    // Reads the ZCode MCP config shape:
    // {"mcp":{"servers":{"<name>":{"type":"stdio","command":…,"args":[…]}}}}
    public static func parseServers(from data: Data) -> [McpServerEntry]? {
        struct Server: Decodable {
            let command: String?
            let args: [String]?
        }
        struct Config: Decodable {
            let mcp: MCP?
            struct MCP: Decodable {
                let servers: [String: Server]?
            }
        }

        guard let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        let servers = config.mcp?.servers ?? [:]
        return servers
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
}

// A global npm binary's package sits in `<bin>/../lib/node_modules`; the
// owning package is the one whose `bin` manifest names this executable
// (skynet-mcp → @shopee/skynet-base, banking-fe-mcp → @shopee/skynet.bank-fe-flow).
public enum NodeModulesPackageReader {
    public struct Package: Equatable, Sendable {
        public let name: String
        public let version: String
    }

    public static func package(
        owningBinary binaryName: String,
        inBinaryDirectory binaryDirectory: String,
        fileManager: FileManager = .default
    ) -> Package? {
        let nodeModulesURL = URL(fileURLWithPath: binaryDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("lib/node_modules")
        guard let scopes = try? fileManager.contentsOfDirectory(
            atPath: nodeModulesURL.path
        ) else {
            return nil
        }

        var candidates: [URL] = []
        for scope in scopes where !scope.hasPrefix(".") {
            let scopeURL = nodeModulesURL.appendingPathComponent(scope)
            var isDirectory: ObjCBool = false
            guard scope.hasPrefix("@"),
                  fileManager.fileExists(atPath: scopeURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                candidates.append(scopeURL)
                continue
            }
            guard let packages = try? fileManager.contentsOfDirectory(
                atPath: scopeURL.path
            ) else {
                continue
            }
            candidates.append(
                contentsOf: packages.map { scopeURL.appendingPathComponent($0) }
            )
        }

        for candidate in candidates {
            let manifestURL = candidate.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let package = parsePackage(from: data),
                  package.binaries.contains(binaryName)
            else {
                continue
            }
            return Package(name: package.name, version: package.version)
        }
        return nil
    }

    private static func parsePackage(from data: Data) -> (name: String, version: String, binaries: Set<String>)? {
        struct Manifest: Decodable {
            let name: String?
            let version: String?
            let bin: Bin?

            enum Bin: Decodable {
                case single(String)
                case multiple([String: String])

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let value = try? container.decode(String.self) {
                        self = .single(value)
                        return
                    }
                    self = .multiple(try container.decode([String: String].self))
                }

                var names: Set<String> {
                    switch self {
                    case let .single(name):
                        [name]
                    case let .multiple(mapping):
                        Set(mapping.keys)
                    }
                }
            }
        }

        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let name = manifest.name,
              let version = manifest.version
        else {
            return nil
        }
        return (name, version, manifest.bin?.names ?? [])
    }
}

public protocol NpmRegistryLatestFetching: Sendable {
    func latestVersion(of package: String) async -> String?
}

// Reads the "latest" dist-tag from the registries the Skynet MCP packages
// live on. `@shopee/skynet.*` publishes to npm.shopee.io; the pinned
// banking-fe-mcp package only exists on the Nexus bank registry, so both
// are probed in order.
public actor HTTPNpmRegistryClient: NpmRegistryLatestFetching {
    public struct Endpoint: Sendable {
        let url: URL
        let authHost: String

        public init(url: URL, authHost: String) {
            self.url = url
            self.authHost = authHost
        }
    }

    private let endpoints: [Endpoint]
    private let npmrcURL: URL?
    private let session: URLSession

    public init(
        endpoints: [Endpoint] = [
            Endpoint(
                url: URL(string: "https://npm.shopee.io")!,
                authHost: "npm.shopee.io"
            ),
            Endpoint(
                url: URL(
                    string: "https://nexus.npt.seabank.io/repository/npm-bank"
                )!,
                authHost: "nexus.npt.seabank.io"
            ),
        ],
        npmrcURL: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".npmrc"),
        session: URLSession = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            return configuration
        }())
    ) {
        self.endpoints = endpoints
        self.npmrcURL = npmrcURL
        self.session = session
    }

    public func latestVersion(of package: String) async -> String? {
        guard let escaped = addingPercentEncoding(
            forPackage: package
        ) else {
            return nil
        }
        let tokens = loadRegistryTokens()
        for endpoint in endpoints {
            var request = URLRequest(
                url: endpoint.url.appendingPathComponent(escaped)
            )
            if let token = tokens[endpoint.authHost] {
                request.setValue(
                    "Bearer \(token)",
                    forHTTPHeaderField: "Authorization"
                )
            }
            guard let (data, response) = try? await session.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                continue
            }
            // `/latest` serves {"name","version"}; the full packument keeps
            // the answer under dist-tags.
            if let version = Self.parseLatestDocument(from: data)
                ?? Self.parsePackumentDistTag(from: data)
            {
                return version
            }
        }
        return nil
    }

    private func loadRegistryTokens() -> [String: String] {
        guard let npmrcURL,
              let contents = try? String(contentsOf: npmrcURL, encoding: .utf8)
        else {
            return [:]
        }
        return Self.parseRegistryTokens(fromNpmrc: contents)
    }

    static func parseRegistryTokens(fromNpmrc contents: String) -> [String: String] {
        var tokens: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // //host/path/:_authToken=<token>
            guard line.hasPrefix("//"),
                  let tokenRange = line.range(of: ":_authToken=")
            else {
                continue
            }
            let host = String(line[line.index(line.startIndex, offsetBy: 2)..<tokenRange.lowerBound])
                .split(separator: "/")
                .first
                .map(String.init) ?? ""
            let token = String(line[tokenRange.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !host.isEmpty, !token.isEmpty {
                tokens[host] = token
            }
        }
        return tokens
    }

    static func parseLatestDocument(from data: Data) -> String? {
        struct Latest: Decodable {
            let version: String
        }
        return (try? JSONDecoder().decode(Latest.self, from: data))?.version
    }

    static func parsePackumentDistTag(from data: Data) -> String? {
        struct Packument: Decodable {
            let distTags: [String: String]

            enum CodingKeys: String, CodingKey {
                case distTags = "dist-tags"
            }
        }
        return (try? JSONDecoder().decode(Packument.self, from: data))?.distTags["latest"]
    }

    func addingPercentEncoding(forPackage package: String) -> String? {
        package.replacingOccurrences(of: "/", with: "%2F")
    }
}

public protocol McpVersionChecking: Sendable {
    func checkVersions() async -> [McpVersionFinding]
}

// Detection only: the findings name the installed and latest versions; the
// upgrade itself is the CLI's `skynet update tools` / npm's job.
public actor McpVersionChecker: McpVersionChecking {
    private let configURL: URL
    private let registry: any NpmRegistryLatestFetching
    private let binarySearchPaths: [String]
    private let fileManager: FileManager

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode/cli/config.json"),
        registry: any NpmRegistryLatestFetching,
        binarySearchPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
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
        guard let data = try? Data(contentsOf: configURL),
              let entries = McpConfigParser.parseServers(from: data)
        else {
            return []
        }

        return await withTaskGroup(of: McpVersionFinding.self) { group in
            for entry in entries {
                group.addTask {
                    await self.finding(for: entry)
                }
            }
            var findings: [McpVersionFinding] = []
            for await finding in group {
                findings.append(finding)
            }
            return findings.sorted { $0.serverName < $1.serverName }
        }
    }

    private func finding(for entry: McpServerEntry) async -> McpVersionFinding {
        guard let plan = McpServerPlan.plan(
            command: entry.command,
            arguments: entry.arguments
        ) else {
            return await resolvedFinding(
                for: entry,
                command: entry.command,
                packageName: nil
            )
        }

        switch plan {
        case let .npxUnpinned(package):
            // An unpinned npx entry resolves fresh on every launch; there is
            // nothing installed to fall behind.
            return McpVersionFinding(
                serverName: entry.name,
                packageName: package,
                unpinned: true
            )

        case let .npxPinned(package, pinnedVersion):
            return McpVersionFinding(
                serverName: entry.name,
                packageName: package,
                installedVersion: pinnedVersion,
                latestVersion: await registry.latestVersion(of: package)
            )

        case let .globalBinary(binaryName, binaryDirectory):
            return await resolvedFinding(
                for: entry,
                command: binaryDirectory + "/" + binaryName,
                packageName: nil
            )
        }
    }

    // Global binaries need the package manifest for a version; when the
    // configured path does not exist (bare command name, moved nvm), the
    // nvm search paths get a chance to locate the same binary elsewhere.
    private func resolvedFinding(
        for entry: McpServerEntry,
        command: String,
        packageName: String?
    ) async -> McpVersionFinding {
        var directory = (command as NSString).deletingLastPathComponent
        let binaryName = (command as NSString).lastPathComponent
        if !fileManager.fileExists(atPath: command) {
            let candidate = binarySearchPaths
                .map { ($0 as NSString).appendingPathComponent(binaryName) }
                .first { fileManager.fileExists(atPath: $0) }
            guard let resolved = candidate else {
                return McpVersionFinding(serverName: entry.name)
            }
            directory = (resolved as NSString).deletingLastPathComponent
        }
        guard let package = NodeModulesPackageReader.package(
            owningBinary: binaryName,
            inBinaryDirectory: directory,
            fileManager: fileManager
        ) else {
            return McpVersionFinding(serverName: entry.name)
        }
        return McpVersionFinding(
            serverName: entry.name,
            packageName: package.name,
            installedVersion: package.version,
            latestVersion: await registry.latestVersion(of: package.name)
        )
    }
}
