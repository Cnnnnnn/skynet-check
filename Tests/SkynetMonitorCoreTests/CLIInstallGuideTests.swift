import XCTest
@testable import SkynetMonitorCore

final class CLIInstallGuideTests: XCTestCase {
    func testUsesDocumentedNodeAndSkynetInstallCommands() {
        XCTAssertEqual(
            CLIInstallGuide.nodeCommand,
            "brew install node"
        )
        XCTAssertEqual(
            CLIInstallGuide.skynetCommand,
            "npm install @shopee/skynet-cli -g --registry https://npm.shopee.io"
        )
    }

    func testProvidesACombinedCopyableCommand() {
        XCTAssertEqual(
            CLIInstallGuide.combinedCommand,
            "brew install node && npm install @shopee/skynet-cli -g --registry https://npm.shopee.io"
        )
    }

    func testUsesCLIUpdateCommand() {
        XCTAssertEqual(CLIInstallGuide.updateCommand, "skynet update")
    }

    func testUsesRepairAndSyncCommands() {
        XCTAssertEqual(CLIInstallGuide.skillSyncCommand, "skynet skill install")
        XCTAssertEqual(CLIInstallGuide.mcpRepairCommand, "skynet update tools")
        XCTAssertEqual(CLIInstallGuide.mcpInstallCommand, "skynet mcp install")
    }

    func testNpxPinnedMcpGetsConfigPinBumpNotSkynetInstall() {
        let finding = McpVersionFinding(
            serverName: "Banking FE MCP",
            packageName: "@shopee/banking-fe-mcp",
            installedVersion: "0.2.27",
            latestVersion: "0.2.29",
            isNPXPinned: true,
            configSource: "Codex"
        )

        let command = CLIInstallGuide.mcpUpgradeCommand(for: finding)

        XCTAssertEqual(
            command,
            """
            python3 <<'PY'
            from pathlib import Path
            path = Path.home() / ".codex/config.toml"
            old = "@shopee/banking-fe-mcp@0.2.27"
            new = "@shopee/banking-fe-mcp@0.2.29"
            text = path.read_text()
            if old not in text:
                raise SystemExit(f"pin not found in {path}: {old}")
            path.write_text(text.replace(old, new, 1))
            print(f"updated {path}: {old} → {new}")
            PY
            """
        )
        XCTAssertFalse(command?.contains("skynet mcp install") == true)
    }

    func testSkynetPrefixedServerUsesNpmInstall() {
        let finding = McpVersionFinding(
            serverName: "skynet-bank-fe-flow",
            packageName: "@shopee/skynet.bank-fe-flow",
            installedVersion: "0.8.9",
            latestVersion: "0.9.0",
            configSource: "Cursor"
        )

        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeCommand(for: finding),
            "npm install -g @shopee/skynet.bank-fe-flow@0.9.0 --registry https://npm.shopee.io"
        )
    }

    func testSkynetBaseUsesNpmWhenCommandIsBareName() {
        let finding = McpVersionFinding(
            serverName: "skynet-base",
            packageName: "@shopee/skynet-base",
            installedVersion: "2.11.5",
            latestVersion: "2.12.3",
            configSource: "Codex",
            configuredCommand: "skynet-mcp"
        )

        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeCommand(for: finding),
            "npm install -g @shopee/skynet-base@2.12.3 --registry https://npm.shopee.io"
        )
    }

    func testSkynetBaseUsesPinnedNpmWhenCursorFixesNvmPath() {
        let finding = McpVersionFinding(
            serverName: "skynet-base",
            packageName: "@shopee/skynet-base",
            installedVersion: "2.9.1",
            latestVersion: "2.12.3",
            configSource: "Cursor",
            configuredCommand: "/Users/me/.nvm/versions/node/v22.22.3/bin/skynet-mcp"
        )

        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeCommand(for: finding),
            [
                "/Users/me/.nvm/versions/node/v22.22.3/bin/npm",
                "install -g @shopee/skynet-base@2.12.3",
                "--registry https://npm.shopee.io",
                "--prefix '/Users/me/.nvm/versions/node/v22.22.3'",
            ].joined(separator: " ")
        )
    }

    func testPlanAndGenFastPinnedPathUsesThatNodesNpm() {
        let finding = McpVersionFinding(
            serverName: "skynet-plan-and-gen-fast",
            packageName: "@shopee/skynet.plan-and-gen-fast",
            installedVersion: "0.4.6",
            latestVersion: "0.4.8",
            configSource: "Cursor",
            configuredCommand: "/Users/me/.nvm/versions/node/v22.23.2/bin/skynet.plan-and-gen",
            configuredBinaryMissing: true
        )

        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeCommand(for: finding),
            [
                "/Users/me/.nvm/versions/node/v22.23.2/bin/npm",
                "install -g @shopee/skynet.plan-and-gen-fast@0.4.8",
                "--registry https://npm.shopee.io",
                "--prefix '/Users/me/.nvm/versions/node/v22.23.2'",
            ].joined(separator: " ")
        )
    }
}
