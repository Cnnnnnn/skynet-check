public enum StatusTint: Equatable, Sendable {
    case secondary
    case green
    case red
    case yellow
}

public struct LoginStatePresentation: Equatable, Sendable {
    public let title: String
    public let symbolName: String
    public let tint: StatusTint

    public init(title: String, symbolName: String, tint: StatusTint) {
        self.title = title
        self.symbolName = symbolName
        self.tint = tint
    }
}

public extension LoginState {
    var presentation: LoginStatePresentation {
        switch self {
        case .checking:
            LoginStatePresentation(
                title: "正在检查",
                symbolName: "circle.dotted",
                tint: .secondary
            )
        case .authenticated:
            LoginStatePresentation(
                title: "已登录",
                symbolName: "checkmark.circle.fill",
                tint: .green
            )
        case .unauthenticated:
            LoginStatePresentation(
                title: "登录已失效",
                symbolName: "exclamationmark.circle.fill",
                tint: .red
            )
        case .offline:
            LoginStatePresentation(
                title: "网络不可用",
                symbolName: "wifi.exclamationmark",
                tint: .yellow
            )
        case .serviceError:
            LoginStatePresentation(
                title: "暂时无法检查",
                symbolName: "wifi.exclamationmark",
                tint: .yellow
            )
        case .cliMissing:
            LoginStatePresentation(
                title: "未找到 Skynet CLI",
                symbolName: "questionmark.circle",
                tint: .secondary
            )
        }
    }

    var authenticatedEmail: String? {
        guard case let .authenticated(email) = self else {
            return nil
        }
        return email
    }
}
