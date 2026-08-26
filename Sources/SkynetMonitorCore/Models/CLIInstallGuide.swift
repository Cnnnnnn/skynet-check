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

    // Upgrade command the user can paste into Terminal.
    // - skynet-base with an absolute command path: install into THAT nvm
    //   prefix (Cursor often pins v22.22.3 while `nvm use 22` is v22.23.2).
    //   Otherwise `skynet update tools` only refreshes the active shell node.
    // - Other platform MCPs: bare `skynet mcp install 'foo'`.
    // - Plain npx pins: bump package@old in the IDE config.
    public static func mcpUpgradeCommand(
        for finding: McpVersionFinding
    ) -> String? {
        guard finding.isUpgradable else {
            return nil
        }

        if finding.serverName == "skynet-base"
            || finding.packageName == "@shopee/skynet-base"
        {
            if let npm = npmForPinnedBinary(finding.configuredCommand),
               let latest = finding.latestVersion
            {
                return "\(npm) install -g @shopee/skynet-base@\(latest) --registry \(SkynetEndpoints.npmRegistryBase)"
            }
            return mcpRepairCommand
        }

        if finding.isNPXPinned,
           let package = finding.packageName,
           let from = finding.installedVersion,
           let to = finding.latestVersion
        {
            return mcpPinBumpCommand(
                package: package,
                from: from,
                to: to,
                configPath: finding.configSource == "Codex"
                    ? SkynetEndpoints.codexConfigPath
                    : SkynetEndpoints.cursorConfigPath
            )
        }

        let installName = skynetInstallName(fromServerName: finding.serverName)
        return "\(mcpInstallCommand) \(shellSingleQuoted(installName))"
    }

    // One command per distinct upgrade target (Cursor/Codex duplicates of
    // the same server collapse unless they pin different binary paths).
    public static func mcpUpgradeScript(
        for findings: [McpVersionFinding]
    ) -> String? {
        var seen = Set<String>()
        var commands: [String] = []
        for finding in findings {
            let key = finding.isNPXPinned
                ? "pin:\(finding.configSource):\(finding.packageName ?? finding.serverName)"
                : "mcp:\(finding.configSource):\(skynetInstallName(fromServerName: finding.serverName)):\(finding.configuredCommand ?? "")"
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

    // Cursor pins e.g. ~/.nvm/versions/node/v22.22.3/bin/skynet-mcp — upgrade
    // must use that node's npm, not whatever `nvm use` selected in the shell.
    private static func npmForPinnedBinary(_ configuredCommand: String?) -> String? {
        guard let configuredCommand,
              configuredCommand.contains("/")
        else {
            return nil
        }
        let npm = URL(fileURLWithPath: configuredCommand)
            .deletingLastPathComponent()
            .appendingPathComponent("npm")
            .path
        return npm
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
