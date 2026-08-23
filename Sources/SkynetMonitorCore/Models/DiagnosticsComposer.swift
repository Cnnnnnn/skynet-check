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
        sessionExpiryOutlived: Bool = false,
        pollingIntervalMinutes: Int,
        notificationPermission: NotificationPermissionStatus,
        permissionAudit: SkynetPermissionAudit?,
        environment: EnvironmentReport?,
        tokenValidation: [String: ServiceTokenValidationOutcome] = [:],
        checkDurations: CheckDurationStats = CheckDurationStats(),
        skynetConfig: SkynetConfigSummary? = nil,
        networkStability: NetworkStability = NetworkStability(),
        skillUpdatePhase: ComponentUpdatePhase = .idle,
        skillUpdateReport: SkillUpdateReport? = nil,
        mcpVersionFindings: [McpVersionFinding] = [],
        now: Date = Date()
    ) -> String {
        var lines: [String] = []
        lines.append("Skynet Login Monitor 诊断信息")
        lines.append("生成时间：\(format(now))")
        appendStatusLines(
            to: &lines,
            appVersion: appVersion,
            state: state,
            lastCheckedAt: lastCheckedAt,
            lastCompletedState: lastCompletedState,
            sessionExpiresAt: sessionExpiresAt,
            sessionExpiryOutlived: sessionExpiryOutlived,
            now: now
        )
        lines.append("自动检查间隔：\(pollingIntervalMinutes) 分钟")
        lines.append("通知权限：\(notificationPermission.diagnosticDetail)")
        appendEnvironmentLines(
            to: &lines,
            permissionAudit: permissionAudit,
            environment: environment,
            skynetConfig: skynetConfig
        )
        if let last = checkDurations.last {
            let average = checkDurations.average.map {
                " · 平均 \(DurationPresentation.summarizeSeconds($0))"
            } ?? ""
            lines.append(
                "检查耗时：最近 \(DurationPresentation.summarizeSeconds(last))\(average)"
            )
        }
        lines.append(
            contentsOf: componentVersionLines(
                phase: skillUpdatePhase,
                report: skillUpdateReport,
                findings: mcpVersionFindings
            )
        )
        appendNetworkAndTokenLines(
            to: &lines,
            networkStability: networkStability,
            tokenValidation: tokenValidation,
            now: now
        )
        return lines.joined(separator: "\n")
    }

    private static func appendStatusLines(
        to lines: inout [String],
        appVersion: String?,
        state: LoginState?,
        lastCheckedAt: Date?,
        lastCompletedState: LoginState?,
        sessionExpiresAt: Date?,
        sessionExpiryOutlived: Bool,
        now: Date
    ) {
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
            lines.append(
                SessionExpiryPresentation.diagnosticsLine(
                    expiresAt: sessionExpiresAt,
                    now: now
                )
            )
        } else if sessionExpiryOutlived {
            lines.append(MonitorText.SessionExpiry.diagnosticsOutlived)
        }
    }

    private static func appendEnvironmentLines(
        to lines: inout [String],
        permissionAudit: SkynetPermissionAudit?,
        environment: EnvironmentReport?,
        skynetConfig: SkynetConfigSummary?
    ) {
        if let permissionAudit, permissionAudit.hasDirectory {
            lines.append(
                "配置权限：目录 \(modeText(permissionAudit.directoryMode))"
                    + " / session \(modeText(permissionAudit.sessionMode))"
                    + " / config \(modeText(permissionAudit.configMode))"
            )
        }
        if let environment {
            lines.append("环境：")
            for check in environment.checks {
                lines.append("- \(check.name)：\(check.detail)")
            }
        }
        guard let skynetConfig else { return }
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

    private static func appendNetworkAndTokenLines(
        to lines: inout [String],
        networkStability: NetworkStability,
        tokenValidation: [String: ServiceTokenValidationOutcome],
        now: Date
    ) {
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
    }

    private static func format(_ date: Date) -> String {
        date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    // Compact component-version lines: one summary per category, with a few
    // named examples so a pasted report stays readable without listing every
    // drifted skill.
    private static func componentVersionLines(
        phase: ComponentUpdatePhase,
        report: SkillUpdateReport?,
        findings: [McpVersionFinding]
    ) -> [String] {
        var lines: [String] = []
        switch phase {
        case .completed:
            if let report {
                if report.updates.isEmpty {
                    lines.append(
                        "组件版本：Skill \(report.totalChecked) 个均为最新"
                    )
                } else {
                    let examples = report.updates
                        .prefix(3)
                        .map { "\($0.name) \($0.installedVersion) → \($0.latestVersion)" }
                        .joined(separator: "、")
                    let suffix = report.updates.count > 3
                        ? " 等 \(report.updates.count) 个" : ""
                    lines.append(
                        "组件版本：Skill \(report.updates.count)/\(report.totalChecked) 可升级（\(examples)\(suffix)）"
                    )
                }
            }
        case .needsLogin:
            lines.append("组件版本：Skill 更新检测需登录后可用")
        case .idle, .checking, .failed:
            break
        }

        let upgradableMCPs = findings.filter(\.isUpgradable)
        if !upgradableMCPs.isEmpty {
            let details = upgradableMCPs
                .map { finding in
                    let installed = finding.installedVersion ?? "?"
                    return "\(finding.serverName) \(installed) → \(finding.latestVersion ?? "?")"
                }
                .joined(separator: "、")
            lines.append("组件版本：MCP 可升级 \(details)")
        }
        return lines
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
