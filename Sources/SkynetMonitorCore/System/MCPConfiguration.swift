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

public struct InstalledSkill: Equatable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct OutdatedSkill: Equatable, Sendable {
    public let name: String
    public let installedVersion: String?
    public let expectedVersion: String

    public init(name: String, installedVersion: String?, expectedVersion: String) {
        self.name = name
        self.installedVersion = installedVersion
        self.expectedVersion = expectedVersion
    }
}

public struct MCPConfiguration: Equatable, Sendable {
    public let mcpSummary: MCPListSummary?
    public let skillCount: Int?
    public let outdatedSkills: [OutdatedSkill]?

    public init(
        mcpSummary: MCPListSummary?,
        skillCount: Int?,
        outdatedSkills: [OutdatedSkill]? = nil
    ) {
        self.mcpSummary = mcpSummary
        self.skillCount = skillCount
        self.outdatedSkills = outdatedSkills
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

public enum SkillInventoryParser {
    public static func parseInstalledSkills(fromJSON data: Data) -> [InstalledSkill]? {
        struct Entry: Decodable {
            let name: String
            let version: String?
        }

        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        return entries.map { InstalledSkill(name: $0.name, version: $0.version ?? "") }
    }

    public static func parseLockBaseline(fromJSON data: Data) -> [String: String]? {
        struct Entry: Decodable {
            let version: String?
        }

        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return nil
        }
        var baseline: [String: String] = [:]
        for (name, entry) in entries {
            baseline[name] = entry.version ?? ""
        }
        return baseline
    }
}

public enum SkillUpdateEvaluator {
    // A skill is outdated when the team lock baseline expects a newer
    // numeric version than what is installed; a baseline entry missing from
    // the installed list counts as outdated, an unparsable expected version
    // is ignored.
    public static func outdatedSkills(
        installed: [InstalledSkill],
        baseline: [String: String]
    ) -> [OutdatedSkill] {
        let installedVersions = Dictionary(
            installed.map { ($0.name, $0.version) },
            uniquingKeysWith: { first, _ in first }
        )

        return baseline
            .compactMap { name, expected -> OutdatedSkill? in
                guard let expectedVersion = SemanticVersion(expected) else {
                    return nil
                }
                let installedRaw = installedVersions[name] ?? ""
                if let installedVersion = SemanticVersion(installedRaw),
                   installedVersion >= expectedVersion
                {
                    return nil
                }
                return OutdatedSkill(
                    name: name,
                    installedVersion: installedRaw.isEmpty ? nil : installedRaw,
                    expectedVersion: expected
                )
            }
            .sorted { $0.name < $1.name }
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
