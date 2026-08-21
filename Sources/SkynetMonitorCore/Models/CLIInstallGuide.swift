public enum CLIInstallGuide {
    public static let nodeCommand = "brew install node"
    public static let skynetCommand =
        "npm install @shopee/skynet-cli -g --registry https://npm.shopee.io"
    public static let combinedCommand =
        "\(nodeCommand) && \(skynetCommand)"
    public static let updateCommand = "skynet update"
    public static let skillSyncCommand = "skynet skill install"
    public static let mcpRepairCommand = "skynet update tools"

    // Upgrading locked skills to the platform's latest main version; the
    // no-argument form only restores the (possibly stale) local lock.
    public static func skillUpgradeCommand(names: [String]) -> String {
        let specs = names.map { "\($0)@latest" }
        return "\(skillSyncCommand) \(specs.joined(separator: " "))"
    }
}
