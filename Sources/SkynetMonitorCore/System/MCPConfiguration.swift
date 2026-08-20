import Foundation

public struct MCPListSummary: Equatable, Sendable {
    public let total: Int
    public let ideGroups: [String: Int]
    public let skynetBaseIDEs: [String]

    public init(
        total: Int,
        ideGroups: [String: Int],
        skynetBaseIDEs: [String]
    ) {
        self.total = total
        self.ideGroups = ideGroups
        self.skynetBaseIDEs = skynetBaseIDEs
    }
}

public struct MCPConfiguration: Equatable, Sendable {
    public let mcpSummary: MCPListSummary?
    public let skillCount: Int?

    public init(mcpSummary: MCPListSummary?, skillCount: Int?) {
        self.mcpSummary = mcpSummary
        self.skillCount = skillCount
    }
}

public enum MCPOutputParser {
    public static let coreMCPName = "skynet-base"

    public static func parseMCPList(_ output: String) -> MCPListSummary? {
        let totalPattern = /找到\s*(\d+)\s*个/
        let ideGroupPattern = /^\[(.+?)\]\s*\((\d+)\)$/
        let entryPattern = /^\d+[.]\s*([^\s(]+)/

        guard let totalMatch = output.firstMatch(of: totalPattern),
              let total = Int(totalMatch.1)
        else {
            return nil
        }

        var ideGroups: [String: Int] = [:]
        var skynetBaseIDEs: [String] = []
        var currentIDE: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let groupMatch = trimmed.firstMatch(of: ideGroupPattern) {
                currentIDE = String(groupMatch.1)
                ideGroups[currentIDE!] = Int(groupMatch.2) ?? 0
            } else if let entryMatch = trimmed.firstMatch(of: entryPattern),
                      String(entryMatch.1) == coreMCPName,
                      let ide = currentIDE,
                      !skynetBaseIDEs.contains(ide)
            {
                skynetBaseIDEs.append(ide)
            }
        }

        return MCPListSummary(
            total: total,
            ideGroups: ideGroups,
            skynetBaseIDEs: skynetBaseIDEs
        )
    }

    public static func parseSkillCount(_ output: String) -> Int? {
        let skillCountPattern = /(\d+)\s*个已安装/
        guard let match = output.firstMatch(of: skillCountPattern) else {
            return nil
        }
        return Int(match.1)
    }
}

enum CLIExecutionEnvironment {
    // Skynet CLI is a node script whose shebang resolves node from PATH;
    // the GUI app's PATH lacks nvm directories, so the CLI's own bin
    // directory is prepended like SkynetAuthChecker does.
    static func base(
        for cliURL: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["PATH"] = [
            cliURL.deletingLastPathComponent().path,
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
        return environment
    }
}
