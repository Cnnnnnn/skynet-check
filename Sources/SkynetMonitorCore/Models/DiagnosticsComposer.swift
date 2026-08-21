import Foundation

// Builds the plain-text report behind the panel's "复制诊断" action.
// Includes only metadata the user would paste into a team thread: the CLI
// stderr detail attached to serviceError is intentionally reduced to the
// state title here.
public enum DiagnosticsComposer {
    public static func compose(
        appVersion: String?,
        state: LoginState?,
        lastCheckedAt: Date?,
        lastCompletedState: LoginState?,
        sessionExpiresAt: Date?,
        pollingIntervalMinutes: Int,
        notificationPermission: NotificationPermissionStatus,
        permissionAudit: SkynetPermissionAudit?,
        environment: EnvironmentReport?,
        tokenValidation: [String: ServiceTokenValidationOutcome] = [:],
        checkDurations: CheckDurationStats = CheckDurationStats(),
        skynetConfig: SkynetConfigSummary? = nil,
        networkStability: NetworkStability = NetworkStability(),
        now: Date = Date()
    ) -> String {
        var lines: [String] = []
        lines.append("Skynet Login Monitor 诊断信息")
        lines.append("生成时间：\(format(now))")
        if let appVersion, !appVersion.isEmpty {
            lines.append("应用版本：\(appVersion)")
        }
        if let state {
            lines.append("当前状态：\(state.presentation.title)")
        }
        if let lastCheckedAt, let lastCompletedState {
            lines.append(
                "最近检查：\(format(lastCheckedAt)) · \(lastCompletedState.presentation.title)"
            )
        }
        if let sessionExpiresAt {
            lines.append("会话预计过期：\(format(sessionExpiresAt))（基于历史观察估算）")
        }
        lines.append("自动检查间隔：\(pollingIntervalMinutes) 分钟")
        lines.append("通知权限：\(notificationPermission.diagnosticDetail)")
        if let permissionAudit, permissionAudit.hasDirectory {
            lines.append(
                "配置权限：目录 \(modeText(permissionAudit.directoryMode)) / session \(modeText(permissionAudit.sessionMode)) / config \(modeText(permissionAudit.configMode))"
            )
        }
        if let environment {
            lines.append("环境：")
            for check in environment.checks {
                lines.append("- \(check.name)：\(check.detail)")
            }
        }
        if let skynetConfig {
            var fields: [String] = []
            if let mode = skynetConfig.mode {
                fields.append("mode=\(mode)")
            }
            if let role = skynetConfig.role {
                fields.append("role=\(role)")
            }
            if let language = skynetConfig.language {
                fields.append("language=\(language)")
            }
            if !fields.isEmpty {
                lines.append("Skynet 配置：\(fields.joined(separator: " "))")
            }
        }
        if let last = checkDurations.last {
            let average = checkDurations.average.map {
                " · 平均 \(DurationPresentation.summarizeSeconds($0))"
            } ?? ""
            lines.append(
                "检查耗时：最近 \(DurationPresentation.summarizeSeconds(last))\(average)"
            )
        }
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        let recentOutages = networkStability.outages(since: dayAgo)
        if !recentOutages.isEmpty {
            let downtime = networkStability.totalDowntime(since: dayAgo)
            lines.append(
                "网络稳定性：24h 掉线 \(recentOutages.count) 次 · 累计 \(DurationPresentation.summarize(downtime))"
            )
        }
        for (key, outcome) in tokenValidation.sorted(by: { $0.key < $1.key }) {
            lines.append("- Token \(key)：\(outcome.panelDetail)")
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ date: Date) -> String {
        date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private static func modeText(_ mode: Int?) -> String {
        mode.map { String(format: "%o", $0) } ?? "无"
    }
}

extension NotificationPermissionStatus {
    var diagnosticDetail: String {
        switch self {
        case .authorized:
            "已授权"
        case .notDetermined:
            "尚未确认"
        case .denied:
            "已拒绝"
        case .unsupported:
            "当前环境不支持"
        }
    }
}
