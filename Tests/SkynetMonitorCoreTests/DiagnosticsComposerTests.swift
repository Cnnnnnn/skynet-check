import Foundation
import XCTest
@testable import SkynetMonitorCore

final class DiagnosticsComposerTests: XCTestCase {
    func testComposesKeyDiagnosticFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let environment = EnvironmentReport(
            cliPath: "/opt/homebrew/bin/skynet",
            cliVersion: "2.7.29",
            nodeVersion: "v22.23.2",
            networkAvailable: true
        )

        let report = DiagnosticsComposer.compose(
            appVersion: "0.3.0",
            state: .authenticated(email: "user@example.com"),
            lastCheckedAt: now.addingTimeInterval(-60),
            lastCompletedState: .authenticated(email: nil),
            sessionExpiresAt: now.addingTimeInterval(3600),
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: SkynetPermissionAudit(
                directoryMode: 0o700,
                sessionMode: 0o600,
                configMode: 0o600
            ),
            environment: environment,
            now: now
        )

        XCTAssertTrue(report.contains("应用版本：0.3.0"))
        XCTAssertTrue(report.contains("当前状态：已登录"))
        XCTAssertTrue(report.contains("会话预计过期"))
        XCTAssertTrue(report.contains("基于历史观察估算"))
        XCTAssertTrue(report.contains("自动检查间隔：15 分钟"))
        XCTAssertTrue(report.contains("通知权限：已授权"))
        XCTAssertTrue(report.contains("配置权限：目录 700"))
        XCTAssertTrue(report.contains("- Skynet CLI：/opt/homebrew/bin/skynet"))
        XCTAssertTrue(report.contains("- Node.js：v22.23.2"))
    }

    func testPastSessionEstimateMarksCLIAsAuthority() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let report = DiagnosticsComposer.compose(
            appVersion: nil,
            state: .authenticated(email: nil),
            lastCheckedAt: now,
            lastCompletedState: .authenticated(email: nil),
            sessionExpiresAt: now.addingTimeInterval(-3600),
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            now: now
        )

        XCTAssertTrue(report.contains("以 CLI 状态为准"))
    }

    func testOutlivedEstimateUsesDedicatedDiagnosticsLine() {
        let report = DiagnosticsComposer.compose(
            appVersion: nil,
            state: .authenticated(email: nil),
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            sessionExpiryOutlived: true,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil
        )

        XCTAssertTrue(report.contains("已超过历史最短估算"))
    }

    func testIncludesConfigSummaryAndCheckDurations() {
        var durations = CheckDurationStats()
        durations.record(0.8)
        durations.record(1.2)

        let report = DiagnosticsComposer.compose(
            appVersion: "0.6.0",
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            checkDurations: durations,
            skynetConfig: SkynetConfigSummary(
                mode: "codex_app",
                role: "FE",
                language: "zh"
            )
        )

        XCTAssertTrue(report.contains("Skynet 配置：mode=codex_app role=FE language=zh"))
        XCTAssertTrue(report.contains("检查耗时：最近 1.2s · 平均 1.0s"))
    }

    func testOmitsEmptyConfigAndDurations() {
        let report = DiagnosticsComposer.compose(
            appVersion: nil,
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil
        )

        XCTAssertFalse(report.contains("Skynet 配置"))
        XCTAssertFalse(report.contains("检查耗时"))
    }

    func testOmitsServiceErrorDetail() {
        let report = DiagnosticsComposer.compose(
            appVersion: "0.3.0",
            state: .serviceError(message: "Error: internal registry detail"),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCompletedState: .serviceError(message: "Error: internal registry detail"),
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil
        )

        XCTAssertTrue(report.contains("暂时无法检查"))
        XCTAssertFalse(report.contains("internal registry detail"))
    }
}
