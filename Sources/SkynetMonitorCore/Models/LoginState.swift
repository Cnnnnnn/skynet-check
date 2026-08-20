public enum LoginState: Equatable, Sendable {
    case checking
    case authenticated(email: String?)
    case unauthenticated
    case offline
    case serviceError(message: String)
    case cliMissing
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
}
