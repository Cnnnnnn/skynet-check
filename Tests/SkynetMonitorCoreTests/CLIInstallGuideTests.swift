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
}
