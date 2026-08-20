import Foundation

public enum CLIPathError: Error, Equatable {
    case notFound
}

public protocol CLIPathLocating: Sendable {
    func locate() async throws -> URL
}

public actor CLIPathLocator: CLIPathLocating {
    private static let cacheKey = "resolvedSkynetCLIPath"

    private let shellResolver: LoginShellResolver
    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private let candidatePaths: [URL]

    public init(
        runner: any CommandRunning,
        defaultsSuiteName: String? = nil,
        candidatePaths: [URL]? = nil
    ) {
        self.shellResolver = LoginShellResolver(runner: runner)
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.candidatePaths = candidatePaths ?? Self.defaultCandidatePaths()
    }

    public func locate() async throws -> URL {
        // Probe well-known install locations on every call: a stale cache
        // entry (e.g. an older nvm-managed version) must not shadow a
        // newer CLI that appeared at a candidate path.
        for candidate in candidatePaths {
            if let candidateURL = executableURL(for: candidate.path) {
                MonitorLog.cli.info("resolved skynet via candidate path")
                defaults.set(candidateURL.path, forKey: Self.cacheKey)
                return candidateURL
            }
        }

        if let cachedPath = defaults.string(forKey: Self.cacheKey),
           let cachedURL = executableURL(for: cachedPath)
        {
            MonitorLog.cli.info("resolved skynet via cached path")
            return cachedURL
        }

        guard
            let output = await shellResolver.resolve(command: "command -v skynet"),
            let firstLine = output
                .components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty }),
            let discoveredURL = executableURL(for: firstLine)
        else {
            MonitorLog.cli.error("skynet CLI not found in candidates, cache, or login shell")
            throw CLIPathError.notFound
        }

        MonitorLog.cli.info("resolved skynet via login shell")
        defaults.set(discoveredURL.path, forKey: Self.cacheKey)
        return discoveredURL
    }

    private func executableURL(for path: String) -> URL? {
        guard path.hasPrefix("/"),
              fileManager.fileExists(atPath: path),
              fileManager.isExecutableFile(atPath: path)
        else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private static func defaultCandidatePaths() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/skynet"),
            URL(fileURLWithPath: "/usr/local/bin/skynet"),
            home.appendingPathComponent(".local/bin/skynet"),
        ]

        let nvmRoot = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(
                contentsOf: versions
                    .sorted {
                        isNewerVersion(
                            $0.lastPathComponent,
                            $1.lastPathComponent
                        )
                    }
                    .map { $0.appendingPathComponent("bin/skynet") }
            )
        }

        return candidates
    }

    // Lexicographic ordering would rank "v9.x" above "v10.x"; the numeric
    // segments must be compared as integers to pick the newest node first.
    // Lexicographic ordering would rank "v9.x" above "v10.x"; the numeric
    // segments must be compared as integers to pick the newest node first.
    static func isNewerVersion(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhsVersion = SemanticVersion(lhs),
              let rhsVersion = SemanticVersion(rhs)
        else {
            return false
        }
        return lhsVersion > rhsVersion
    }
}
