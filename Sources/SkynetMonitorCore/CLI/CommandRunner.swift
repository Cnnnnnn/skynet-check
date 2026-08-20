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
            return await execution.run(timeout: timeout)
        }.value
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private static let killGracePeriod: Duration = .seconds(2)

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

    func run(timeout: Duration) async -> CommandResult {
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

        // Both pipes must be drained while the child runs: a child that
        // fills the pipe buffer blocks on write and never exits, which
        // would deadlock waitUntilExit below.
        let stdoutReader = Task.detached(priority: .utility) {
            self.readToEnd(self.standardOutput.fileHandleForReading)
        }
        let stderrReader = Task.detached(priority: .utility) {
            self.readToEnd(self.standardError.fileHandleForReading)
        }

        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else {
                return
            }
            await self.terminateStalledProcess()
        }

        process.waitUntilExit()
        watchdog.cancel()

        let outputData = await stdoutReader.value
        let errorData = await stderrReader.value
        let timedOut = lock.withLock { didTimeOut }

        // Log metadata only: command output may contain account details.
        let commandName = process.executableURL?.lastPathComponent ?? "process"
        let exitCode = process.terminationStatus
        MonitorLog.runner.info(
            "command \(commandName, privacy: .public) exit=\(exitCode) timedOut=\(timedOut) stdoutBytes=\(outputData.count) stderrBytes=\(errorData.count)"
        )

        return CommandResult(
            stdout: String(decoding: outputData, as: UTF8.self),
            stderr: String(decoding: errorData, as: UTF8.self),
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private func readToEnd(_ handle: FileHandle) -> Data {
        handle.readDataToEndOfFile()
    }

    private func terminateStalledProcess() async {
        let didTerminate = lock.withLock { () -> Bool in
            guard process.isRunning else {
                return false
            }
            didTimeOut = true
            process.terminate()
            return true
        }
        guard didTerminate else {
            return
        }

        try? await Task.sleep(for: Self.killGracePeriod)
        guard !Task.isCancelled else {
            return
        }
        lock.withLock {
            guard process.isRunning else {
                return
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
