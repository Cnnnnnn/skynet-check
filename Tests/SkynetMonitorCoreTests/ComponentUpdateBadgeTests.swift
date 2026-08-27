import XCTest
@testable import SkynetMonitorCore

final class ComponentUpdateBadgeTests: XCTestCase {
    func testUpgradableBadgeUsesCountBeforeNoun() {
        XCTAssertEqual(
            MonitorText.ComponentUpdate.upgradableBadge(skillCount: 0, mcpCount: 6),
            "6 个 MCP 可升级"
        )
        XCTAssertEqual(
            MonitorText.ComponentUpdate.upgradableBadge(skillCount: 2, mcpCount: 6),
            "2 个 Skill · 6 个 MCP 可升级"
        )
    }

    func testMcpFindingsSortUpgradableAndMismatchFirst() {
        let current = McpVersionFinding(
            serverName: "ok",
            packageName: "@x/ok",
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            configSource: "Cursor"
        )
        let mismatch = McpVersionFinding(
            serverName: "stale-node",
            packageName: "@x/stale",
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            configSource: "Cursor",
            configuredCommand: "/Users/me/.nvm/versions/node/v22.22.3/bin/x",
            pathNvmNode: "v22.23.2"
        )
        let upgradable = McpVersionFinding(
            serverName: "behind",
            packageName: "@x/behind",
            installedVersion: "1.0.0",
            latestVersion: "2.0.0",
            configSource: "Codex"
        )

        let sorted = McpVersionFinding.sortedForDisplay([
            current,
            mismatch,
            upgradable,
        ])

        XCTAssertEqual(sorted.map(\.serverName), ["behind", "stale-node", "ok"])
        // Upgradable + mismatch outranks mismatch alone.
        XCTAssertEqual(upgradable.displayAttentionRank, 2)
        XCTAssertEqual(mismatch.displayAttentionRank, 1)
        XCTAssertEqual(current.displayAttentionRank, 0)
    }
}
