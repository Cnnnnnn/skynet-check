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
    var isAuthenticated: Bool {
        guard case .authenticated = self else {
            return false
        }
        return true
    }
}

public extension LoginState {
    var presentation: LoginStatePresentation {
        switch self {
        case .checking:
            LoginStatePresentation(
                title: MonitorText.StateTitle.checking,
                symbolName: "circle.dotted",
                tint: .secondary
            )
        case .authenticated:
            LoginStatePresentation(
                title: MonitorText.StateTitle.authenticated,
                symbolName: "checkmark.circle.fill",
                tint: .green
            )
        case .unauthenticated:
            LoginStatePresentation(
                title: MonitorText.StateTitle.unauthenticated,
                symbolName: "exclamationmark.circle.fill",
                tint: .red
            )
        case .offline:
            LoginStatePresentation(
                title: MonitorText.StateTitle.offline,
                symbolName: "wifi.exclamationmark",
                tint: .yellow
            )
        case .serviceError:
            LoginStatePresentation(
                title: MonitorText.StateTitle.serviceUnavailable,
                symbolName: "wifi.exclamationmark",
                tint: .yellow
            )
        case .cliMissing:
            LoginStatePresentation(
                title: MonitorText.StateTitle.cliMissing,
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
