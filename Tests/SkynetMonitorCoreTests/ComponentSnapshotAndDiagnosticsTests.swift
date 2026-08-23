import Foundation
import XCTest
@testable import SkynetMonitorCore

@MainActor
final class ComponentSnapshotAndDiagnosticsTests: XCTestCase {
    // MARK: - diagnostics

    func testDiagnosticsIncludeComponentVersions() {
        let report = DiagnosticsComposer.compose(
            appVersion: "0.7.0",
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            skillUpdatePhase: .completed,
            skillUpdateReport: SkillUpdateReport(
                totalChecked: 56,
                updates: [
                    SkillUpdate(name: "a-skill", installedVersion: "v1", latestVersion: "v2"),
                    SkillUpdate(name: "b-skill", installedVersion: "v3", latestVersion: "v4"),
                ]
            ),
            mcpVersionFindings: [
                McpVersionFinding(
                    serverName: "skynet-base",
                    installedVersion: "2.11.5",
                    latestVersion: "2.12.2"
                ),
            ]
        )

        XCTAssertTrue(report.contains("组件版本：Skill 2/56 可升级（a-skill v1 → v2、b-skill v3 → v4）"))
        XCTAssertTrue(report.contains("组件版本：MCP 可升级 skynet-base 2.11.5 → 2.12.2"))
    }

    func testDiagnosticsAllCurrentAndNeedsLogin() {
        let current = DiagnosticsComposer.compose(
            appVersion: nil,
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            skillUpdatePhase: .completed,
            skillUpdateReport: SkillUpdateReport(totalChecked: 12, updates: [])
        )
        XCTAssertTrue(current.contains("组件版本：Skill 12 个均为最新"))

        let needsLogin = DiagnosticsComposer.compose(
            appVersion: nil,
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            skillUpdatePhase: .needsLogin
        )
        XCTAssertTrue(needsLogin.contains("组件版本：Skill 更新检测需登录后可用"))
    }

    // MARK: - snapshot cache

    func testSnapshotStoreRoundTrips() {
        let defaults = UserDefaults(
            suiteName: "component-update-tests-\(UUID().uuidString)"
        )!
        let store = ComponentUpdateSnapshotStore(defaults: defaults)
        let savedAt = Date(timeIntervalSince1970: 1_755_800_000)
        let snapshot = ComponentUpdateSnapshot(
            savedAt: savedAt,
            skillPhase: .completed,
            skillReport: SkillUpdateReport(
                totalChecked: 3,
                updates: [
                    SkillUpdate(name: "a", installedVersion: "v1", latestVersion: "v2"),
                ]
            ),
            mcpFindings: [
                McpVersionFinding(
                    serverName: "banking",
                    packageName: "@shopee/banking-fe-mcp",
                    installedVersion: "0.2.27",
                    latestVersion: "0.2.29",
                    isNPXPinned: true
                ),
            ]
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    @MainActor
    func testStoreRestoresSnapshotOnInitAndSavesAfterCheck() async {
        let defaults = UserDefaults(
            suiteName: "component-update-tests-\(UUID().uuidString)"
        )!
        let snapshotStore = ComponentUpdateSnapshotStore(defaults: defaults)
        let savedAt = Date(timeIntervalSince1970: 1_755_800_000)
        snapshotStore.save(
            ComponentUpdateSnapshot(
                savedAt: savedAt,
                skillPhase: .completed,
                skillReport: SkillUpdateReport(totalChecked: 7, updates: []),
                mcpFindings: []
            )
        )
        let restored = makeStore(
            skillChecker: MutableSkillUpdateChecker(),
            snapshotStore: snapshotStore
        )

        XCTAssertEqual(restored.skillUpdatePhase, .completed)
        XCTAssertEqual(restored.skillUpdateReport?.totalChecked, 7)
        XCTAssertEqual(restored.componentUpdateCheckedAt, savedAt)

        let checker = MutableSkillUpdateChecker()
        let active = makeStore(
            skillChecker: checker,
            snapshotStore: snapshotStore
        )
        checker.result = .completed(
            SkillUpdateReport(totalChecked: 9, updates: [])
        )
        await active.checkComponentUpdates()

        let saved = snapshotStore.load()
        XCTAssertEqual(saved?.skillReport?.totalChecked, 9)
        // Snapshots encode whole seconds; compare with second-level accuracy.
        XCTAssertEqual(
            active.componentUpdateCheckedAt?.timeIntervalSince1970 ?? 0,
            saved?.savedAt.timeIntervalSince1970 ?? 0,
            accuracy: 1.0
        )
    }

    @MainActor
    func testRefreshRechecksComponentsOnlyWhenDue() async throws {
        final class MutableClock: @unchecked Sendable {
            var date = Date(timeIntervalSince1970: 1_755_800_000)
        }
        let clock = MutableClock()
        let checker = MutableSkillUpdateChecker()
        checker.result = .completed(
            SkillUpdateReport(totalChecked: 1, updates: [])
        )
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            skillUpdateChecker: checker,
            now: { clock.date }
        )

        await store.checkComponentUpdates()
        XCTAssertEqual(checker.callCount, 1)

        await store.refresh()
        XCTAssertEqual(checker.callCount, 1, "not due within two hours")

        clock.date = clock.date.addingTimeInterval(2 * 60 * 60 + 60)
        await store.refresh()
        for _ in 0..<200 where checker.callCount < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(checker.callCount, 2, "due after two hours")
    }

    // MARK: - component-update notification

    @MainActor
    func testComponentUpdateNotificationFiresOncePerEpisode() async {
        let skillChecker = MutableSkillUpdateChecker()
        let notifier = StubNotifier()
        let mcpChecker = MutableMcpVersionChecker()
        skillChecker.result = .completed(
            SkillUpdateReport(
                totalChecked: 10,
                updates: [
                    SkillUpdate(name: "a", installedVersion: "v1", latestVersion: "v2"),
                ]
            )
        )
        mcpChecker.findings = [
            McpVersionFinding(
                serverName: "skynet-base",
                installedVersion: "2.11.5",
                latestVersion: "2.12.2"
            ),
        ]
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: notifier,
            periodicInterval: nil,
            skillUpdateChecker: skillChecker,
            mcpVersionChecker: mcpChecker
        )

        await store.checkComponentUpdates()
        await store.checkComponentUpdates()
        XCTAssertEqual(notifier.componentUpdateNotifications.count, 1)
        XCTAssertEqual(notifier.componentUpdateNotifications.first?.skillCount, 1)
        XCTAssertEqual(notifier.componentUpdateNotifications.first?.mcpCount, 1)

        // Clean result re-arms the notification.
        skillChecker.result = .completed(
            SkillUpdateReport(totalChecked: 10, updates: [])
        )
        mcpChecker.findings = []
        await store.checkComponentUpdates()
        XCTAssertEqual(notifier.componentUpdateNotifications.count, 1)

        skillChecker.result = .completed(
            SkillUpdateReport(
                totalChecked: 10,
                updates: [
                    SkillUpdate(name: "a", installedVersion: "v2", latestVersion: "v3"),
                ]
            )
        )
        await store.checkComponentUpdates()
        XCTAssertEqual(notifier.componentUpdateNotifications.count, 2)
    }

    // MARK: - helpers

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
}
