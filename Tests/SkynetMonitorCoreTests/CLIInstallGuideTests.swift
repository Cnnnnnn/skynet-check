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

    func testMissingBinaryInstallsToPathNodeAndRetargetsConfig() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let finding = McpVersionFinding(
            serverName: "skynet-base",
            packageName: "@shopee/skynet-base",
            installedVersion: "2.9.1",
            latestVersion: "2.12.3",
            configSource: "Cursor",
            configuredCommand:
                "\(home)/.nvm/versions/node/v22.22.3/bin/skynet-mcp",
            configuredBinaryMissing: true,
            pathNvmNode: "v22.23.2"
        )

        let command = CLIInstallGuide.mcpUpgradeCommand(for: finding)

        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeExpectation(for: finding),
            MonitorText.ComponentUpdate.upgradeExpectNpmMissingToPath
        )
        let install = [
            "\(home)/.nvm/versions/node/v22.23.2/bin/npm",
            "install -g @shopee/skynet-base@2.12.3",
            "--registry https://npm.shopee.io",
            "--prefix '\(home)/.nvm/versions/node/v22.23.2'",
        ].joined(separator: " ")
        XCTAssertTrue(
            command?.hasPrefix(install) == true,
            "expected PATH-node install, got: \(command ?? "nil")"
        )
        XCTAssertTrue(
            command?.contains("/.nvm/versions/node/v22.22.3/") == true
        )
        XCTAssertTrue(
            command?.contains("path = Path.home() / \".cursor/mcp.json\"") == true
        )
    }

    func testUpgradeStrategyAndExpectationMatchCommandPaths() {
        let pin = McpVersionFinding(
            serverName: "Banking FE MCP",
            packageName: "@shopee/banking-fe-mcp",
            installedVersion: "0.2.27",
            latestVersion: "0.2.29",
            isNPXPinned: true,
            configSource: "Codex"
        )
        XCTAssertEqual(CLIInstallGuide.mcpUpgradeStrategy(for: pin), .pinBump)
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeExpectation(for: pin),
            MonitorText.ComponentUpdate.upgradeExpectPin
        )

        let bareNpm = McpVersionFinding(
            serverName: "skynet-bank-fe-flow",
            packageName: "@shopee/skynet.bank-fe-flow",
            installedVersion: "0.8.9",
            latestVersion: "0.9.0",
            configSource: "Cursor"
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeStrategy(for: bareNpm),
            .npmInstall(usesPinnedNode: false)
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeExpectation(for: bareNpm),
            MonitorText.ComponentUpdate.upgradeExpectNpm
        )

        let pinnedNpm = McpVersionFinding(
            serverName: "skynet-base",
            packageName: "@shopee/skynet-base",
            installedVersion: "2.9.1",
            latestVersion: "2.12.3",
            configSource: "Cursor",
            configuredCommand: "/Users/me/.nvm/versions/node/v22.22.3/bin/skynet-mcp"
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeStrategy(for: pinnedNpm),
            .npmInstall(usesPinnedNode: true)
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeExpectation(for: pinnedNpm),
            MonitorText.ComponentUpdate.upgradeExpectNpmPinned
        )

        let lastResort = McpVersionFinding(
            serverName: "skynet-mystery",
            installedVersion: "1.0.0",
            latestVersion: "1.1.0",
            configSource: "Cursor"
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeStrategy(for: lastResort),
            .skynetMcpInstall
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeExpectation(for: lastResort),
            MonitorText.ComponentUpdate.upgradeExpectSkynetInstall
        )

        let updateTools = McpVersionFinding(
            serverName: "skynet-base",
            installedVersion: "2.9.1",
            latestVersion: "2.12.3",
            configSource: "Codex"
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeStrategy(for: updateTools),
            .skynetUpdateTools
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpUpgradeExpectation(for: updateTools),
            MonitorText.ComponentUpdate.upgradeExpectUpdateTools
        )
    }

    func testNvmPathParsesNodeVersion() {
        XCTAssertEqual(
            NvmPaths.nodeVersion(
                inPath: "/Users/me/.nvm/versions/node/v22.23.2/bin/node"
            ),
            "v22.23.2"
        )
        XCTAssertNil(NvmPaths.nodeVersion(inPath: "/usr/local/bin/node"))
    }

    func testFindingDerivesConfiguredNvmAndMismatch() {
        let matched = McpVersionFinding(
            serverName: "skynet-base",
            configuredCommand: "/Users/me/.nvm/versions/node/v22.23.2/bin/skynet-mcp",
            pathNvmNode: "v22.23.2"
        )
        XCTAssertEqual(matched.configuredNvmNode, "v22.23.2")
        XCTAssertNil(matched.pathNvmNode)
        XCTAssertFalse(matched.hasNvmNodeMismatch)

        let mismatched = matched.annotating(pathNvmNode: "v22.22.3")
        XCTAssertEqual(mismatched.pathNvmNode, "v22.22.3")
        XCTAssertTrue(mismatched.hasNvmNodeMismatch)
    }

    func testRetargetNvmCommandRewritesFrozenPath() {
        let finding = McpVersionFinding(
            serverName: "skynet-base",
            configSource: "Cursor",
            configuredCommand: "/Users/me/.nvm/versions/node/v22.22.3/bin/skynet-mcp",
            pathNvmNode: "v22.23.2"
        )

        let command = CLIInstallGuide.mcpRetargetNvmCommand(for: finding)

        XCTAssertEqual(
            command,
            """
            python3 <<'PY'
            from pathlib import Path
            path = Path.home() / ".cursor/mcp.json"
            old = "/.nvm/versions/node/v22.22.3/"
            new = "/.nvm/versions/node/v22.23.2/"
            text = path.read_text()
            if old not in text:
                raise SystemExit(f"nvm path not found in {path}: {old}")
            path.write_text(text.replace(old, new))
            print(f"updated {path}: {old} → {new}")
            PY
            """
        )
        XCTAssertEqual(
            CLIInstallGuide.mcpRetargetNvmFindings(from: [finding, finding]).count,
            1
        )
    }
}
