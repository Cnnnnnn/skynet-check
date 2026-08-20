import Foundation

public enum EnvironmentCheckStatus: Equatable, Sendable {
    case passed
    case warning
    case failed
}

public struct EnvironmentCheck: Equatable, Sendable {
    public let name: String
    public let status: EnvironmentCheckStatus
    public let detail: String

    public init(
        name: String,
        status: EnvironmentCheckStatus,
        detail: String
    ) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct EnvironmentReport: Equatable, Sendable {
    public let cliPath: String?
    public let cliVersion: String?
    public let nodeVersion: String?
    public let networkAvailable: Bool

    public init(
        cliPath: String?,
        cliVersion: String?,
        nodeVersion: String?,
        networkAvailable: Bool
    ) {
        self.cliPath = cliPath
        self.cliVersion = cliVersion
        self.nodeVersion = nodeVersion
        self.networkAvailable = networkAvailable
    }

    public var checks: [EnvironmentCheck] {
        [
            EnvironmentCheck(
                name: "Skynet CLI",
                status: cliPath == nil ? .failed : .passed,
                detail: cliPath ?? "未找到可执行文件"
            ),
            EnvironmentCheck(
                name: "Node.js",
                status: nodeVersion == nil ? .failed : .passed,
                detail: nodeVersion ?? "未找到 Node.js"
            ),
            EnvironmentCheck(
                name: "网络",
                status: networkAvailable ? .passed : .warning,
                detail: networkAvailable ? "网络可用" : "网络不可用"
            ),
        ]
    }
}

public actor EnvironmentDoctor {
    private let locator: any CLIPathLocating
    private let checker: any SkynetAuthChecking
    private let shellResolver: LoginShellResolver

    public init(
        locator: any CLIPathLocating,
        checker: any SkynetAuthChecking,
        runner: any CommandRunning
    ) {
        self.locator = locator
        self.checker = checker
        self.shellResolver = LoginShellResolver(runner: runner)
    }

    public func inspect(networkAvailable: Bool) async -> EnvironmentReport {
        let cliURL = try? await locator.locate()
        let nodeVersion = await discoverNodeVersion()
        return EnvironmentReport(
            cliPath: cliURL?.path,
            cliVersion: await checker.version(),
            nodeVersion: nodeVersion,
            networkAvailable: networkAvailable
        )
    }

    private func discoverNodeVersion() async -> String? {
        guard
            let output = await shellResolver.resolve(command: "node --version")
        else {
            return nil
        }
        let version = output
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return version?.isEmpty == false ? version : nil
    }
}
