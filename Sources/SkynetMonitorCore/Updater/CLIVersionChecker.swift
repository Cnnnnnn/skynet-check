import Foundation

public protocol CLIVersionChecking: Sendable {
    func fetchLatest() async throws -> String
}

// Reads the "latest" dist-tag from the internal npm registry so the app can
// tell when the installed Skynet CLI falls behind, without shelling out to
// npm or adding a hard dependency on the local Node environment.
public actor RegistryCLIVersionChecker: CLIVersionChecking {
    private let registryURL: URL
    private let session: URLSession

    public init(
        registryURL: URL = URL(
            string: "https://npm.shopee.io/@shopee%2Fskynet-cli/latest"
        )!,
        session: URLSession = .shared
    ) {
        self.registryURL = registryURL
        self.session = session
    }

    public func fetchLatest() async throws -> String {
        let (data, _) = try await session.data(from: registryURL)
        return try Self.parseLatestVersion(from: data)
    }

    static func parseLatestVersion(from data: Data) throws -> String {
        struct Latest: Decodable {
            let version: String
        }

        return try JSONDecoder().decode(Latest.self, from: data).version
    }
}

public extension EnvironmentReport {
    // True when both versions are known and the registry version sorts
    // newer than the installed one.
    var isCLIBehindLatest: Bool {
        guard let cliVersion,
              let latestCLIVersion,
              let current = SemanticVersion(cliVersion),
              let latest = SemanticVersion(latestCLIVersion)
        else {
            return false
        }
        return latest > current
    }

    // The probes ran and found something `skynet update tools` can fix:
    // no MCP configured at all, or IDEs with MCP but without the core one.
    var needsMCPRepair: Bool {
        guard let summary = mcpConfiguration?.mcpSummary else {
            return false
        }
        if summary.total == 0 {
            return true
        }
        let missingCore = summary.ideGroups.keys
            .filter { !summary.skynetBaseIDEs.contains($0) }
        return !missingCore.isEmpty
    }
}
