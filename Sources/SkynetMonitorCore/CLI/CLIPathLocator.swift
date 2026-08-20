import Foundation

public enum CLIPathError: Error, Equatable {
    case notFound
}

public protocol CLIPathLocating: Sendable {
    func locate() async throws -> URL
}

public actor CLIPathLocator: CLIPathLocating {
    private static let cacheKey = "resolvedSkynetCLIPath"

    private let runner: any CommandRunning
    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private let candidatePaths: [URL]

    public init(
        runner: any CommandRunning,
        defaultsSuiteName: String? = nil,
        candidatePaths: [URL]? = nil
    ) {
        self.runner = runner
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.candidatePaths = candidatePaths ?? Self.defaultCandidatePaths()
    }

    public func locate() async throws -> URL {
        if let cachedPath = defaults.string(forKey: Self.cacheKey),
           let cachedURL = executableURL(for: cachedPath)
        {
            return cachedURL
        }

        for candidate in candidatePaths {
            if let candidateURL = executableURL(for: candidate.path) {
                defaults.set(candidateURL.path, forKey: Self.cacheKey)
                return candidateURL
            }
        }

        let result = await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-l", "-i", "-c", "command -v skynet"],
            environment: ProcessInfo.processInfo.environment,
            timeout: .seconds(5)
        )

        guard !result.timedOut,
              result.exitCode == 0,
              let discoveredURL = executableURL(
                for: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
              )
        else {
            throw CLIPathError.notFound
        }

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
                    .sorted { $0.path > $1.path }
                    .map { $0.appendingPathComponent("bin/skynet") }
            )
        }

        return candidates
    }
}
