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

        let state = AuthOutputParser.parse(AuthOutput(result))

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
            return LoginActionResult(state: currentState)
        }

        guard let executableURL = try? await locator.locate() else {
            return LoginActionResult(state: .cliMissing)
        }

        // The login flow opens a browser and waits for the user to finish
        // authenticating, which routinely takes longer than a minute.
        let result = await runner.run(
            executableURL: executableURL,
            arguments: ["auth", "login"],
            environment: environment(for: executableURL),
            timeout: .seconds(300)
        )
        let loginURL = LoginURLExtractor.firstURL(in: result.stdout)

        if !networkAvailable && (result.timedOut || result.exitCode != 0) {
            return LoginActionResult(state: .offline, loginURL: loginURL)
        }
        guard !result.timedOut, result.exitCode == 0 else {
            return LoginActionResult(
                state: .serviceError(
                    message: AuthOutputParser.errorDetail(
                        for: AuthOutput(result),
                        fallback: "Skynet login failed"
                    )
                ),
                loginURL: loginURL
            )
        }

        return LoginActionResult(
            state: await check(networkAvailable: networkAvailable),
            loginURL: loginURL
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
        CLIExecutionEnvironment.base(
            for: executableURL,
            base: baseEnvironment
        )
    }
}
