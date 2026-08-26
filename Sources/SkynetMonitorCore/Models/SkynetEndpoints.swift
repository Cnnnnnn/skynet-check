import Foundation

// Single source of truth for internal endpoints and well-known config
// paths. When an environment moves, this is the only file to touch.
public enum SkynetEndpoints {
    // MARK: npm registries

    public static let npmRegistryBase = "https://npm.shopee.io"
    public static let npmBankRegistryURL =
        "https://nexus.npt.seabank.io/repository/npm-bank"
    public static let npmBankAuthHost = "nexus.npt.seabank.io"

    // MARK: platform services

    public static let skillPlatformBase = "https://de.shopee.io"
    public static let confluenceBase = "https://confluence.shopee.io"

    // MARK: config paths (relative to the user's home)

    public static let cursorConfigPath = ".cursor/mcp.json"
    public static let codexConfigPath = ".codex/config.toml"
    public static let sessionPath = ".skynet-cli/session.json"
    public static let tokensPath = ".skynet-cli/tokens.json"

    // MARK: helpers

    public static func homeRelative(_ relative: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relative)
    }

    public static var cursorConfigURL: URL {
        homeRelative(cursorConfigPath)
    }

    public static var codexConfigURL: URL {
        homeRelative(codexConfigPath)
    }
}
