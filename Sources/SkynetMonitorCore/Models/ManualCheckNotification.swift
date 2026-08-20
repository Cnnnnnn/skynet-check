public struct ManualCheckNotification: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public extension LoginState {
    var manualCheckNotification: ManualCheckNotification? {
        switch self {
        case .checking:
            nil
        case let .authenticated(email):
            ManualCheckNotification(
                title: "Skynet 登录状态正常",
                body: email.map { "\($0) 当前登录有效。" } ?? "当前登录有效。"
            )
        case .unauthenticated:
            ManualCheckNotification(
                title: "Skynet 可能已退出登录",
                body: "将在 30 秒后自动复核。"
            )
        case .offline:
            ManualCheckNotification(
                title: "Skynet 暂时无法检查",
                body: "网络不可用，请恢复网络后重试。"
            )
        case .serviceError:
            ManualCheckNotification(
                title: "Skynet 状态检查失败",
                body: "服务暂时不可用，请稍后重试。"
            )
        case .cliMissing:
            ManualCheckNotification(
                title: "未找到 Skynet CLI",
                body: "请确认 Skynet CLI 已安装并可在终端运行。"
            )
        }
    }
}
