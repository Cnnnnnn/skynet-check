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
}
