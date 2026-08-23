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

public extension CommandRunning {
    // Streaming variant; the default falls back to the buffered run and
    // ignores the callback so existing conformances keep working.
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> CommandResult {
        await run(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        await run(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            onLine: { _ in }
        )
    }

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> CommandResult {
        await Task.detached(priority: .utility) {
            let execution = ProcessExecution(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                onOutputLine: onLine
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
    private let onOutputLine: (@Sendable (String) -> Void)?

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) {
        self.onOutputLine = onOutputLine
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
        // would deadlock waitUntilExit below. Lines stream to onOutputLine
        // as they arrive so long-running commands can surface output early.
        let stdoutReader = Task.detached(priority: .utility) {
            await self.readLines(
                from: self.standardOutput.fileHandleForReading,
                onLine: self.onOutputLine
            )
        }
        let stderrReader = Task.detached(priority: .utility) {
            await self.readLines(
                from: self.standardError.fileHandleForReading,
                onLine: nil
            )
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
        let summary = "command \(commandName) exit=\(process.terminationStatus) "
            + "timedOut=\(timedOut) stdoutBytes=\(outputData.count) "
            + "stderrBytes=\(errorData.count)"
        MonitorLog.runner.info("\(summary, privacy: .public)")

        return CommandResult(
            stdout: String(decoding: outputData, as: UTF8.self),
            stderr: String(decoding: errorData, as: UTF8.self),
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private func readLines(
        from handle: FileHandle,
        onLine: (@Sendable (String) -> Void)?
    ) async -> Data {
        let stream = AsyncStream<Data> { continuation in
            handle.readabilityHandler = { fileHandle in
                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    fileHandle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
        }

        var collected = Data()
        var pending = Data()
        for await chunk in stream {
            collected.append(chunk)
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending.prefix(upTo: newline)
                if !lineData.isEmpty,
                   let line = String(bytes: lineData, encoding: .utf8) {
                    onLine?(line)
                }
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        if !pending.isEmpty,
           let line = String(bytes: pending, encoding: .utf8) {
            onLine?(line)
        }
        return collected
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
