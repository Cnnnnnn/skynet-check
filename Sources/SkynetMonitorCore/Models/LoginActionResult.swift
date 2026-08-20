public enum LoginActionResult: Equatable, Sendable {
    case alreadyAuthenticated(email: String?)
    case completed(LoginState)

    public var state: LoginState {
        switch self {
        case let .alreadyAuthenticated(email):
            .authenticated(email: email)
        case let .completed(state):
            state
        }
    }

    public var notification: ManualCheckNotification {
        switch self {
        case let .alreadyAuthenticated(email):
            ManualCheckNotification(
                title: "Skynet 当前已登录",
                body: email.map {
                    "\($0) 当前登录有效，无需重新登录。"
                } ?? "当前登录有效，无需重新登录。"
            )
        case let .completed(.authenticated(email)):
            ManualCheckNotification(
                title: "Skynet 登录成功",
                body: email.map { "已登录为 \($0)。" } ?? "登录已完成。"
            )
        case .completed(.offline):
            ManualCheckNotification(
                title: "Skynet 登录失败",
                body: "网络不可用，请恢复网络后重试。"
            )
        case .completed(.cliMissing):
            ManualCheckNotification(
                title: "无法启动 Skynet 登录",
                body: "未找到 Skynet CLI。"
            )
        case .completed(.serviceError):
            ManualCheckNotification(
                title: "Skynet 登录失败",
                body: "登录服务暂时不可用，请稍后重试。"
            )
        case .completed(.unauthenticated):
            ManualCheckNotification(
                title: "Skynet 登录未完成",
                body: "请再次点击“重新登录”重试。"
            )
        case .completed(.checking):
            ManualCheckNotification(
                title: "Skynet 正在登录",
                body: "请稍候。"
            )
        }
    }
}
