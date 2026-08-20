public enum CLIInstallGuide {
    public static let nodeCommand = "brew install node"
    public static let skynetCommand =
        "npm install @shopee/skynet-cli -g --registry https://npm.shopee.io"
    public static let combinedCommand =
        "\(nodeCommand) && \(skynetCommand)"
    public static let updateCommand = "skynet update"
    public static let skillSyncCommand = "skynet skill install"
    public static let mcpRepairCommand = "skynet update tools"
}
