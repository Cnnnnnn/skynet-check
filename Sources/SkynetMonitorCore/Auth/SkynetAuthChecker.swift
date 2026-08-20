import Foundation

public protocol SkynetAuthChecking: Sendable {
    func check(networkAvailable: Bool) async -> LoginState
    func login(networkAvailable: Bool) async -> LoginActionResult
    func version() async -> String?
}

public actor SkynetAuthChecker: SkynetAuthChecking {
    private let locator: any CLIPathLocating
    private let runner: any CommandRunning
    private let baseEnvironment: [String: String]

    public init(
        locator: any CLIPathLocating,
        runner: any CommandRunning,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.locator = locator
        self.runner = runner
        self.baseEnvironment = baseEnvironment
    }

    public func check(networkAvailable: Bool) async -> LoginState {
        guard let executableURL = try? await locator.locate() else {
            return .cliMissing
        }

        let result = await runner.run(
            executableURL: executableURL,
            arguments: ["auth", "status"],
            environment: environment(for: executableURL),
            timeout: .seconds(8)
        )

        if !networkAvailable && (result.timedOut || result.exitCode != 0) {
            return .offline
        }

        let state = AuthOutputParser.parse(
            AuthOutput(
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                timedOut: result.timedOut
            )
        )

        if !networkAvailable,
           case .serviceError = state
        {
            return .offline
        }

        return state
    }

    public func login(networkAvailable: Bool) async -> LoginActionResult {
        let currentState = await check(networkAvailable: networkAvailable)
        if case let .authenticated(email) = currentState {
            return .alreadyAuthenticated(email: email)
        }
        guard currentState == .unauthenticated else {
            return .completed(currentState)
        }

        guard let executableURL = try? await locator.locate() else {
            return .completed(.cliMissing)
        }

        let result = await runner.run(
            executableURL: executableURL,
            arguments: ["auth", "login"],
            environment: environment(for: executableURL),
            timeout: .seconds(60)
        )

        if !networkAvailable && (result.timedOut || result.exitCode != 0) {
            return .completed(.offline)
        }
        guard !result.timedOut, result.exitCode == 0 else {
            return .completed(
                .serviceError(message: "Skynet login failed")
            )
        }

        return .completed(
            await check(networkAvailable: networkAvailable)
        )
    }

    public func version() async -> String? {
        guard let executableURL = try? await locator.locate() else {
            return nil
        }

        let result = await runner.run(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: environment(for: executableURL),
            timeout: .seconds(3)
        )
        guard !result.timedOut, result.exitCode == 0 else {
            return nil
        }

        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private func environment(for executableURL: URL) -> [String: String] {
        var environment = baseEnvironment
        environment["PATH"] = [
            executableURL.deletingLastPathComponent().path,
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
        return environment
    }
}
