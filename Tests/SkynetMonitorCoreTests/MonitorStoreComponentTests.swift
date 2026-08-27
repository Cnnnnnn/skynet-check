import Foundation
import XCTest
@testable import SkynetMonitorCore

@MainActor
final class MonitorStoreComponentTests: XCTestCase {
    // MARK: - MonitorStore wiring

    @MainActor
    func testCheckComponentUpdatesPublishesResults() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .completed(
            SkillUpdateReport(
                totalChecked: 56,
                updates: [
                    SkillUpdate(
                        name: "fe-api-gen",
                        installedVersion: "v10",
                        latestVersion: "v11"
                    ),
                ]
            )
        )
        let mcpChecker = MutableMcpVersionChecker()
        mcpChecker.findings = [
            McpVersionFinding(
                serverName: "skynet-base",
                packageName: "@shopee/skynet-base",
                installedVersion: "2.11.5",
                latestVersion: "2.12.2"
            ),
        ]
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker,
            mcpVersionChecker: mcpChecker
        )

        XCTAssertTrue(store.showsComponentUpdates)
        await store.checkComponentUpdates()

        XCTAssertEqual(store.skillUpdatePhase, .completed)
        XCTAssertEqual(store.skillUpdateReport?.updates.first?.name, "fe-api-gen")
        XCTAssertEqual(store.mcpVersionFindings.first?.serverName, "skynet-base")
        XCTAssertTrue(store.mcpVersionFindings.first?.isUpgradable ?? false)
    }

    @MainActor
    func testCheckComponentUpdatesPublishesNeedsLogin() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .needsLogin
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker
        )

        await store.checkComponentUpdates()

        XCTAssertEqual(store.skillUpdatePhase, .needsLogin)
        XCTAssertNil(store.skillUpdateReport)
    }

    @MainActor
    func testLoginRechecksComponentsWhenWaitingForLogin() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .needsLogin
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker
        )

        await store.checkComponentUpdates()
        XCTAssertEqual(store.skillUpdatePhase, .needsLogin)

        skillChecker.result = .completed(
            SkillUpdateReport(totalChecked: 5, updates: [])
        )
        await store.login()

        XCTAssertEqual(store.skillUpdatePhase, .completed)
        XCTAssertEqual(store.skillUpdateReport?.totalChecked, 5)
    }

    @MainActor
    func testStoreWithoutCheckersHidesComponentUpdates() async {
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil
        )

        XCTAssertFalse(store.showsComponentUpdates)
        XCTAssertFalse(store.showsUpdateCheck)
        await store.checkComponentUpdates()
        XCTAssertEqual(store.skillUpdatePhase, .idle)
    }

    @MainActor
    private func makeStore(
        skillChecker: MutableSkillUpdateChecker,
        snapshotStore: ComponentUpdateSnapshotStore? = nil
    ) -> MonitorStore {
        MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: skillChecker,
            componentUpdateStore: snapshotStore
        )
    }

    @MainActor
    func testFailedReasonIsPublished() async {
        let checker = MutableSkillUpdateChecker()
        checker.result = .failed(reason: "无法读取 skill lock 文件")
        let store = makeStore(skillChecker: checker)

        await store.checkComponentUpdates()

        XCTAssertEqual(store.skillUpdatePhase, .failed)
        XCTAssertEqual(
            store.skillUpdateFailureDetail,
            "无法读取 skill lock 文件"
        )
    }

    @MainActor
    func testUpgradeCommandMarksPendingRecheckConsumedOnPanelReopen() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .completed(
            SkillUpdateReport(totalChecked: 1, updates: [])
        )
        let store = makeStore(skillChecker: skillChecker)

        store.noteComponentUpgradeCommandUsed()
        XCTAssertTrue(store.pendingComponentRecheckAfterUpgrade)

        await store.recheckComponentsIfUpgradePending()

        XCTAssertFalse(store.pendingComponentRecheckAfterUpgrade)
        XCTAssertEqual(store.skillUpdatePhase, .completed)
    }

    @MainActor
    func testRecheckIfUpgradePendingIsNoOpWhenNotArmed() async {
        let skillChecker = MutableSkillUpdateChecker()
        skillChecker.result = .completed(
            SkillUpdateReport(totalChecked: 1, updates: [])
        )
        let store = makeStore(skillChecker: skillChecker)

        await store.recheckComponentsIfUpgradePending()

        XCTAssertEqual(store.skillUpdatePhase, .idle)
    }
}
