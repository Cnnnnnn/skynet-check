import AppIntents
import Foundation
import SkynetMonitorCore

// Shortcuts integration (macOS: user-built shortcuts in the Shortcuts app;
// App Shortcuts voice phrases are not supported on macOS). Intents run in
// the app's process, so .standard defaults already see the app's domain.

enum LoginIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noStatusYet

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noStatusYet:
            "还没有任何检查结果，请先打开应用完成一次检查"
        }
    }
}

/// Reads the persisted snapshot — instant, no probes, no notifications.
struct GetLoginStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "查询登录状态"
    static let description = IntentDescription(
        "读取最近一次检查的登录状态与会话剩余时间",
        categoryName: "查询"
    )

    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let snapshot = LoginStateStore().load() else {
            throw LoginIntentError.noStatusYet
        }
        let expiryRecord = SessionExpiryStore().load()
        let report = StatusReport.make(
            snapshot: snapshot,
            expiryRecord: expiryRecord,
            now: Date()
        )

        var lines = [
            "状态：\(report.state)",
            "账号：\(report.email ?? "未知")",
        ]
        if report.authenticated,
           let expiresAt = report.sessionExpiresAt,
           let countdown = SessionExpiryPresentation.menuBarCountdown(
                expiresAt: expiresAt,
                now: Date()
           )
        {
            lines.append("预计还剩 \(countdown)")
        } else if report.sessionOutlivedEstimate {
            lines.append("已超过历史最短会话时长")
        }
        let summary = lines.joined(separator: "\n")
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

/// Runs one real probe via the Skynet CLI. Independent of the running
/// monitor; never posts notifications.
struct RefreshLoginStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "立即检查登录"
    static let description = IntentDescription(
        "调用 Skynet CLI 执行一次真实检查并返回最新状态",
        categoryName: "操作"
    )

    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let runner = ProcessCommandRunner()
        let checker = SkynetAuthChecker(
            locator: CLIPathLocator(runner: runner),
            runner: runner
        )
        let state = await checker.check(networkAvailable: true)
        let summary = "最新状态：\(state.presentation.title)"
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

/// Cycles the do-not-disturb window: off → 30min → 1h → 4h → off.
struct CycleNotificationMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "切换通知勿扰"
    static let description = IntentDescription(
        "在关闭 → 30 分钟 → 1 小时 → 4 小时之间循环切换通知暂停窗口",
        categoryName: "操作"
    )

    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = NotificationMuteStore()
        let presets = NotificationMuteWindow.presets  // seconds
        // The current preset is whichever one the remaining window is
        // closest to (within half its length); -1 means not muted.
        let remaining = store.load()?.pausedUntil.timeIntervalSinceNow ?? -1
        let currentIndex = presets.firstIndex { preset in
            remaining > 0 && abs(remaining - preset) < preset / 2
        } ?? -1
        let nextPosition = currentIndex + 1

        if nextPosition >= presets.count {
            store.resume()
            let summary = "通知已恢复"
            return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
        }
        let seconds = presets[nextPosition]
        store.pause(until: Date().addingTimeInterval(seconds))
        let minutes = Int(seconds / 60)
        let summary = minutes < 60 ? "通知已暂停 \(minutes) 分钟" : "通知已暂停 \(minutes / 60) 小时"
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}
