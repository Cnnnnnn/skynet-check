import Foundation

public enum CLIInstallGuide {
    public static let nodeCommand = "brew install node"
    public static let skynetCommand =
        "npm install @shopee/skynet-cli -g --registry https://npm.shopee.io"
    public static let combinedCommand =
        "\(nodeCommand) && \(skynetCommand)"
    public static let updateCommand = "skynet update"
    public static let skillSyncCommand = "skynet skill install"
    public static let mcpRepairCommand = "skynet update tools"
    public static let mcpInstallCommand = "skynet mcp install"

    // Upgrading locked skills to the platform's latest main version; the
    // no-argument form only restores the (possibly stale) local lock.
    public static func skillUpgradeCommand(names: [String]) -> String {
        let specs = names.map { "\($0)@latest" }
        return "\(skillSyncCommand) \(specs.joined(separator: " "))"
    }

    // Which pasteable upgrade path we chose — drives UI expectation copy.
    public enum McpUpgradeStrategy: Equatable, Sendable {
        case pinBump
        case npmInstall(usesPinnedNode: Bool)
        case skynetUpdateTools
        case skynetMcpInstall
    }

    // Upgrade command the user can paste into Terminal.
    // - npx pins: bump package@old in the IDE config.
    // - Resolved npm packages (skynet-base, plan-and-gen-fast, …):
    //   `npm install -g pkg@ver`. Absolute Cursor paths use THAT node's npm
    //   (`skynet mcp install` no-ops when already configured / pending build).
    // - Otherwise: bare `skynet mcp install 'name'`.
    public static func mcpUpgradeCommand(
        for finding: McpVersionFinding
    ) -> String? {
        guard let strategy = mcpUpgradeStrategy(for: finding) else {
            return nil
        }
        switch strategy {
        case .pinBump:
            guard let package = finding.packageName,
                  let from = finding.installedVersion,
                  let to = finding.latestVersion
            else {
                return nil
            }
            return mcpPinBumpCommand(
                package: package,
                from: from,
                to: to,
                configPath: finding.configSource == "Codex"
                    ? SkynetEndpoints.codexConfigPath
                    : SkynetEndpoints.cursorConfigPath
            )
        case .npmInstall:
            guard let package = finding.packageName,
                  let latest = finding.latestVersion
            else {
                return nil
            }
            let install = mcpNpmInstallCommand(
                package: package,
                version: latest,
                configuredCommand: npmInstallAnchor(for: finding)
            )
            // Config points at a missing nvm pin: install into the live PATH
            // node and rewrite the IDE path in one paste when we know both.
            if finding.configuredBinaryMissing,
               let retarget = mcpRetargetNvmCommand(for: finding)
            {
                return install + "\n\n" + retarget
            }
            return install
        case .skynetUpdateTools:
            return mcpRepairCommand
        case .skynetMcpInstall:
            let installName = skynetInstallName(fromServerName: finding.serverName)
            return "\(mcpInstallCommand) \(shellSingleQuoted(installName))"
        }
    }

    public static func mcpUpgradeStrategy(
        for finding: McpVersionFinding
    ) -> McpUpgradeStrategy? {
        guard finding.isUpgradable else {
            return nil
        }

        if finding.isNPXPinned,
           finding.packageName != nil,
           finding.installedVersion != nil,
           finding.latestVersion != nil
        {
            return .pinBump
        }

        if finding.packageName != nil, finding.latestVersion != nil {
            let pinned = npmPrefix(
                forConfiguredCommand: npmInstallAnchor(for: finding)
            ) != nil
            return .npmInstall(usesPinnedNode: pinned)
        }

        if finding.serverName == "skynet-base" {
            return .skynetUpdateTools
        }

        return .skynetMcpInstall
    }

    public static func mcpUpgradeExpectation(
        for finding: McpVersionFinding
    ) -> String? {
        guard let strategy = mcpUpgradeStrategy(for: finding) else {
            return nil
        }
        switch strategy {
        case .pinBump:
            return MonitorText.ComponentUpdate.upgradeExpectPin
        case .npmInstall(let usesPinnedNode):
            if finding.configuredBinaryMissing, finding.pathNvmNode != nil {
                return MonitorText.ComponentUpdate.upgradeExpectNpmMissingToPath
            }
            return usesPinnedNode
                ? MonitorText.ComponentUpdate.upgradeExpectNpmPinned
                : MonitorText.ComponentUpdate.upgradeExpectNpm
        case .skynetUpdateTools:
            return MonitorText.ComponentUpdate.upgradeExpectUpdateTools
        case .skynetMcpInstall:
            return MonitorText.ComponentUpdate.upgradeExpectSkynetInstall
        }
    }

    // Rewrite absolute nvm node dirs in the IDE config so they match the
    // login-shell node (Cursor often freezes an older nvm path).
    public static func mcpRetargetNvmCommand(
        for finding: McpVersionFinding
    ) -> String? {
        guard let from = finding.configuredNvmNode,
              let to = finding.pathNvmNode,
              from != to
        else {
            return nil
        }
        let configPath = finding.configSource == "Codex"
            ? SkynetEndpoints.codexConfigPath
            : SkynetEndpoints.cursorConfigPath
        let old = "/.nvm/versions/node/\(from)/"
        let new = "/.nvm/versions/node/\(to)/"
        return [
            "python3 <<'PY'",
            "from pathlib import Path",
            "path = Path.home() / \"\(configPath)\"",
            "old = \"\(old)\"",
            "new = \"\(new)\"",
            "text = path.read_text()",
            "if old not in text:",
            "    raise SystemExit(f\"nvm path not found in {path}: {old}\")",
            "path.write_text(text.replace(old, new))",
            "print(f\"updated {path}: {old} → {new}\")",
            "PY",
        ].joined(separator: "\n")
    }

    // One row per (IDE, from→to); many servers share the same frozen node.
    public static func mcpRetargetNvmFindings(
        from findings: [McpVersionFinding]
    ) -> [McpVersionFinding] {
        var seen = Set<String>()
        return findings.filter { finding in
            guard let from = finding.configuredNvmNode,
                  let to = finding.pathNvmNode
            else {
                return false
            }
            return seen.insert("\(finding.configSource):\(from):\(to)").inserted
        }
    }

    // One command per distinct upgrade target (Cursor/Codex duplicates of
    // the same server collapse unless they pin different binary paths).
    public static func mcpUpgradeScript(
        for findings: [McpVersionFinding]
    ) -> String? {
        var seen = Set<String>()
        var commands: [String] = []
        for finding in findings {
            let packageKey = finding.packageName
                ?? skynetInstallName(fromServerName: finding.serverName)
            let key = finding.isNPXPinned
                ? "pin:\(finding.configSource):\(packageKey)"
                : "mcp:\(finding.configSource):\(packageKey):\(finding.configuredCommand ?? "")"
            guard seen.insert(key).inserted,
                  let command = mcpUpgradeCommand(for: finding)
            else {
                continue
            }
            commands.append(command)
        }
        guard !commands.isEmpty else {
            return nil
        }
        return commands.joined(separator: "\n\n")
    }

    // When the IDE pin's binary is gone, prefer the login-shell nvm node so
    // `npm --prefix` does not target a deleted Node install.
    private static func npmInstallAnchor(
        for finding: McpVersionFinding
    ) -> String? {
        if finding.configuredBinaryMissing,
           let pathNode = finding.pathNvmNode
        {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".nvm/versions/node")
                .appendingPathComponent(pathNode)
                .appendingPathComponent("bin/npm")
                .path
        }
        return finding.configuredCommand
    }

    private static func mcpNpmInstallCommand(
        package: String,
        version: String,
        configuredCommand: String?
    ) -> String {
        var parts: [String] = []
        if let pinned = npmPrefix(forConfiguredCommand: configuredCommand) {
            parts.append(pinned.npm)
            parts.append("install -g \(package)@\(version)")
            if package.hasPrefix("@shopee/") {
                parts.append("--registry \(SkynetEndpoints.npmRegistryBase)")
            }
            // Some shells leave npm_config_prefix on an older nvm; force
            // the install into the same prefix the IDE binary path uses.
            parts.append("--prefix \(shellSingleQuoted(pinned.prefix))")
        } else {
            parts.append("npm install -g \(package)@\(version)")
            if package.hasPrefix("@shopee/") {
                parts.append("--registry \(SkynetEndpoints.npmRegistryBase)")
            }
        }
        return parts.joined(separator: " ")
    }

    // Cursor pins e.g. ~/.nvm/versions/node/v22.23.2/bin/skynet-mcp — upgrade
    // must use that node's npm AND --prefix, not whatever npm_config_prefix
    // the shell inherited.
    private static func npmPrefix(
        forConfiguredCommand configuredCommand: String?
    ) -> (npm: String, prefix: String)? {
        guard let configuredCommand,
              configuredCommand.contains("/")
        else {
            return nil
        }
        let binDir = URL(fileURLWithPath: configuredCommand)
            .deletingLastPathComponent()
        return (
            npm: binDir.appendingPathComponent("npm").path,
            prefix: binDir.deletingLastPathComponent().path
        )
    }

    // getMCPServerName prefixes non-HTTP installs with "skynet-"; the install
    // argument is the bare platform name. skynet-base is the exception.
    private static func skynetInstallName(fromServerName serverName: String) -> String {
        if serverName == "skynet-base" {
            return serverName
        }
        let prefix = "skynet-"
        if serverName.hasPrefix(prefix) {
            return String(serverName.dropFirst(prefix.count))
        }
        return serverName
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func mcpPinBumpCommand(
        package: String,
        from: String,
        to: String,
        configPath: String
    ) -> String {
        let old = "\(package)@\(from)"
        let new = "\(package)@\(to)"
        return [
            "python3 <<'PY'",
            "from pathlib import Path",
            "path = Path.home() / \"\(configPath)\"",
            "old = \"\(old)\"",
            "new = \"\(new)\"",
            "text = path.read_text()",
            "if old not in text:",
            "    raise SystemExit(f\"pin not found in {path}: {old}\")",
            "path.write_text(text.replace(old, new, 1))",
            "print(f\"updated {path}: {old} → {new}\")",
            "PY",
        ].joined(separator: "\n")
    }
}
