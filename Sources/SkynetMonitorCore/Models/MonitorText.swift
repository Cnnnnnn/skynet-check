import Foundation

// Central home for user-facing text so translations or wording changes
// have a single place to start from. Keep values in Chinese; the panel and
// notifications are Chinese-first by design.

public enum MonitorText {
    public enum StateTitle {
        public static let checking = "正在检查"
        public static let authenticated = "已登录"
        public static let unauthenticated = "登录已失效"
        public static let offline = "网络不可用"
        public static let serviceUnavailable = "暂时无法检查"
        public static let cliMissing = "未找到 Skynet CLI"
    }

    public enum ExpiredNotification {
        public static let title = "Skynet 登录已失效"
        public static let body = "请重新登录，以免 CLI 任务执行时中断。"
    }

    public enum ExpiringNotification {
        public static func title(stage: SessionExpiryAdvisor.Stage) -> String {
            switch stage {
            case .warning:
                return "Skynet 登录即将过期"
            case .urgent:
                return "Skynet 登录马上过期"
            }
        }

        public static func body(stage: SessionExpiryAdvisor.Stage, expiresAt: Date) -> String {
            let time = expiresAt.formatted(date: .omitted, time: .shortened)
            switch stage {
            case .warning:
                return "按历史估算约 \(time) 过期，可点「立即检查」确认。"
            case .urgent:
                return "按历史估算约 \(time) 过期，建议确认 CLI 状态或重新登录。"
            }
        }
    }

    public enum SessionExpiry {
        public static func panelUpcoming(_ time: String) -> String {
            "预计过期：\(time)"
        }
        public static func panelPast(_ time: String) -> String {
            "估算已过期（\(time)）· 以 CLI 为准"
        }
        public static let panelOutlived = "已超过历史最短估算 · 以 CLI 为准"
        public static func diagnosticsUpcoming(_ stamp: String) -> String {
            "会话预计过期：\(stamp)（基于历史观察估算）"
        }
        public static func diagnosticsPast(_ stamp: String) -> String {
            "会话预计过期：\(stamp)（估算已过，以 CLI 状态为准）"
        }
        public static let diagnosticsOutlived = "会话预计过期：已超过历史最短估算（以 CLI 状态为准）"
        public static let scopeCaption = "仅监控本地 CLI，与网页登录无关"
    }

    public enum NotificationAction {
        public static let login = "重新登录"
        public static let check = "立即检查"
    }

    public enum ManualCheckNotification {
        public static let authenticatedTitle = "Skynet 登录状态正常"
        public static let authenticatedBody = "当前登录有效。"
        public static func authenticatedEmailBody(_ email: String) -> String {
            "\(email) 当前登录有效。"
        }

        public static let unauthenticatedTitle = "Skynet 可能已退出登录"
        public static let unauthenticatedBody = "将在 30 秒后自动复核。"

        public static let offlineTitle = "Skynet 暂时无法检查"
        public static let offlineBody = "网络不可用，请恢复网络后重试。"

        public static let serviceErrorTitle = "Skynet 状态检查失败"
        public static let serviceErrorBody = "服务暂时不可用，请稍后重试。"

        public static let cliMissingTitle = "未找到 Skynet CLI"
        public static let cliMissingBody = "请确认 Skynet CLI 已安装并可在终端运行。"
    }

    public enum LoginResultNotification {
        public static let alreadyAuthenticatedTitle = "Skynet 当前已登录"
        public static func alreadyAuthenticatedBody(_ email: String) -> String {
            "\(email) 当前登录有效，无需重新登录。"
        }
        public static let alreadyAuthenticatedBodyFallback = "当前登录有效，无需重新登录。"

        public static let loginSucceededTitle = "Skynet 登录成功"
        public static func loginSucceededEmailBody(_ email: String) -> String {
            "已登录为 \(email)。"
        }
        public static let loginSucceededBody = "登录已完成。"

        public static let offlineTitle = "Skynet 登录失败"
        public static let offlineBody = "网络不可用，请恢复网络后重试。"

        public static let cliMissingTitle = "无法启动 Skynet 登录"
        public static let cliMissingBody = "未找到 Skynet CLI。"

        public static let serviceErrorTitle = "Skynet 登录失败"
        public static let serviceErrorBody = "登录服务暂时不可用，请稍后重试。"

        public static let stillUnauthenticatedTitle = "Skynet 登录未完成"
        public static let stillUnauthenticatedBody = "请再次点击“重新登录”重试。"

        public static let pendingTitle = "Skynet 正在登录"
        public static let pendingBody = "请稍候。"
    }

    public enum Environment {
        public static let cliMissingDetail = "未找到可执行文件"
        public static let nodeMissingDetail = "未找到 Node.js"
        public static let networkAvailableDetail = "网络可用"
        public static let networkUnavailableDetail = "网络不可用"
        public static let skynetBaseFoundDetail = "已安装"
        public static let skynetBaseMissingDetail = "未安装，key 功能不可用"
        public static let mcpUnableToRead = "无法读取 MCP 配置"
        public static let mcpNoneConfigured = "未配置任何 MCP"
        public static func mcpMissingCore(_ ides: String) -> String {
            "skynet-base MCP 未配置于 \(ides)"
        }
        public static func mcpSummary(total: Int, ideCount: Int) -> String {
            "\(total) 个 · \(ideCount) 个 IDE"
        }
        public static let skillUnableToRead = "无法读取 Skills"
        public static let skillNoneInstalled = "未安装任何 Skill"
        public static func skillSummary(_ count: Int) -> String {
            "\(count) 个已安装"
        }
        public static func skillOutdated(total: Int, outdated: Int) -> String {
            "\(total) 个已安装，\(outdated) 个落后于基线"
        }
    }

    public enum Permission {
        public static let repaired = "权限已修复"
        public static let repairFailed = "权限修复失败"
    }

    public enum ServiceToken {
        public static let validDetail = "有效"
        public static let invalidDetail = "已失效"
        public static let unknownDetail = "未检测"

        public static func invalidNotificationTitle(name: String) -> String {
            "\(name) Token 已失效"
        }
        public static let invalidNotificationBody = "相关功能已不可用，请重新获取并更新 token。"
    }

    public enum UpdateCheck {
        public static let upToDate = "已是最新版本"
        public static let failed = "检查更新失败"
    }

    public enum ComponentUpdate {
        public static let cardTitle = "组件版本"
        public static let checking = "正在检查组件版本…"
        public static let needsLogin = "登录后可检测 Skill 更新"
        public static let failed = "组件版本检测失败，可点“重新检查”重试"
        public static let skillSection = "Skill"
        public static let mcpSection = "MCP"
        public static func skillAllCurrent(_ total: Int) -> String {
            "\(total) 个已检查，均为最新"
        }
        public static func skillOutdated(_ count: Int, total: Int) -> String {
            "\(total) 个已检查，\(count) 个可升级"
        }
        public static func skillUpgradeTitle(_ count: Int) -> String {
            "\(count) 个 Skill 可升级"
        }
        public static func mcpUpgradeTitle(_ count: Int) -> String {
            "\(count) 个 MCP 可升级"
        }
        // Collapsed-card badge: "6 个 MCP 可升级", never "MCP 6 可升级".
        public static func upgradableBadge(skillCount: Int, mcpCount: Int) -> String {
            var parts: [String] = []
            if skillCount > 0 {
                parts.append("\(skillCount) 个 Skill")
            }
            if mcpCount > 0 {
                parts.append("\(mcpCount) 个 MCP")
            }
            return parts.joined(separator: " · ") + " \(upgradableSuffix)"
        }
        public static let unpinnedDetail = "未固定版本"
        public static let unavailableDetail = "无法确定"
        public static let upgradableSuffix = "可升级"
        public static let failureReasonPrefix = "原因："
        public static func lastChecked(_ time: String) -> String {
            "上次检查 \(time)"
        }
        public static let copyUpgradeCommand = "复制升级命令"
        public static let copyAllUpgradeCommands = "复制全部升级命令"
        public static let openTerminalUpgrade = "Terminal 升级"
        public static let updatesNotificationTitle = "Skynet 组件有可更新"
        public static func updatesNotificationBody(
            skillCount: Int,
            mcpCount: Int
        ) -> String {
            var parts: [String] = []
            if skillCount > 0 {
                parts.append("\(skillCount) 个 Skill")
            }
            if mcpCount > 0 {
                parts.append("\(mcpCount) 个 MCP")
            }
            return "\(parts.joined(separator: "、"))落后于最新版本，可在菜单栏面板查看。"
        }
    }
}
