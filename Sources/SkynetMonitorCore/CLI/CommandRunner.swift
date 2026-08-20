import Foundation

public struct CommandResult: Equatable, Sendable {
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

public protocol CommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        await Task.detached(priority: .utility) {
            let execution = ProcessExecution(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment
            )
            return execution.run(timeout: timeout)
        }.value
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let process = Process()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let lock = NSLock()
    private var didTimeOut = false

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError
    }

    func run(timeout: Duration) -> CommandResult {
        do {
            try process.run()
        } catch {
            return CommandResult(
                stdout: "",
                stderr: "",
                exitCode: -1,
                timedOut: false
            )
        }

        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else {
                return
            }
            lock.withLock {
                guard process.isRunning else {
                    return
                }
                didTimeOut = true
                process.terminate()
            }
        }

        process.waitUntilExit()
        watchdog.cancel()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            stdout: String(decoding: outputData, as: UTF8.self),
            stderr: String(decoding: errorData, as: UTF8.self),
            exitCode: process.terminationStatus,
            timedOut: lock.withLock { didTimeOut }
        )
    }
}
