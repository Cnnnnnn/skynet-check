public enum LoginState: Equatable, Sendable, Codable {
    case checking
    case authenticated(email: String?)
    case unauthenticated
    case offline
    case serviceError(message: String)
    case cliMissing
}

public extension LoginState {
    // Persisted snapshots must not retain CLI stderr summaries; the detail
    // stays in memory for the panel only.
    var persistenceSafe: LoginState {
        guard case .serviceError = self else {
            return self
        }
        return .serviceError(message: "Skynet CLI reported an error")
    }
}

public struct AuthOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let timedOut: Bool

    public init(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        timedOut: Bool
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
    }

    public init(_ result: CommandResult) {
        self.init(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            timedOut: result.timedOut
        )
    }
}
