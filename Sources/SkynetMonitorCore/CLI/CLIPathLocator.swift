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

    public init(
        runner: any CommandRunning,
        defaultsSuiteName: String? = nil
    ) {
        self.runner = runner
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func locate() async throws -> URL {
        if let cachedPath = defaults.string(forKey: Self.cacheKey),
           let cachedURL = executableURL(for: cachedPath)
        {
            return cachedURL
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
}
