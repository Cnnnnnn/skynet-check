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
    // - npx pins: bump package@old in the IDE config.
    // - Resolved npm packages (skynet-base, plan-and-gen-fast, …):
    //   `npm install -g pkg@ver`. Absolute Cursor paths use THAT node's npm
    //   (`skynet mcp install` no-ops when already configured / pending build).
    // - Otherwise: bare `skynet mcp install 'name'`.
    public static func mcpUpgradeCommand(
        for finding: McpVersionFinding
    ) -> String? {
        guard finding.isUpgradable else {
            return nil
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

        if let package = finding.packageName,
           let latest = finding.latestVersion
        {
            return mcpNpmInstallCommand(
                package: package,
                version: latest,
                configuredCommand: finding.configuredCommand
            )
        }

        if finding.serverName == "skynet-base" {
            return mcpRepairCommand
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
