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
                return "预计 \(time) 过期，建议尽快重新登录。"
            case .urgent:
                return "预计 \(time) 过期，请立即重新登录。"
            }
        }
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
    }

    public enum Permission {
        public static let repaired = "权限已修复"
        public static let repairFailed = "权限修复失败"
    }

    public enum UpdateCheck {
        public static let upToDate = "已是最新版本"
        public static let failed = "检查更新失败"
    }
}
