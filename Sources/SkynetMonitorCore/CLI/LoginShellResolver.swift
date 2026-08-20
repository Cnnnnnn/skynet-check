import Foundation

struct LoginShellResolver: Sendable {
    private let runner: any CommandRunning
    private let timeout: Duration

    init(runner: any CommandRunning, timeout: Duration = .seconds(5)) {
        self.runner = runner
        self.timeout = timeout
    }

    // A non-interactive login shell is fast and side-effect free, but it
    // skips .zshrc where nvm is often initialized — retry interactively.
    func resolve(command: String) async -> String? {
        let invocationModes = [["-l", "-c"], ["-l", "-i", "-c"]]
        for mode in invocationModes {
            let result = await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: mode + [command],
                environment: ProcessInfo.processInfo.environment,
                timeout: timeout
            )
            guard !result.timedOut, result.exitCode == 0 else {
                MonitorLog.cli.debug(
                    "login shell discovery failed for flags \(mode.joined(separator: " "), privacy: .public)"
                )
                continue
            }

            let output = result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                continue
            }
            return output
        }
        return nil
    }
}
