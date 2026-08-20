import Foundation

public enum LoginActionResult: Equatable, Sendable {
    case alreadyAuthenticated(email: String?)
    case completed(LoginState, loginURL: URL?)

    public init(state: LoginState, loginURL: URL? = nil) {
        self = .completed(state, loginURL: loginURL)
    }

    public var state: LoginState {
        switch self {
        case let .alreadyAuthenticated(email):
            .authenticated(email: email)
        case let .completed(state, _):
            state
        }
    }

    public var loginURL: URL? {
        switch self {
        case .alreadyAuthenticated:
            nil
        case let .completed(_, loginURL):
            loginURL
        }
    }

    public var notification: ManualCheckNotification {
        switch self {
        case let .alreadyAuthenticated(email):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.alreadyAuthenticatedTitle,
                body: email.map {
                    MonitorText.LoginResultNotification.alreadyAuthenticatedBody($0)
                } ?? MonitorText.LoginResultNotification.alreadyAuthenticatedBodyFallback
            )
        case let .completed(.authenticated(email), _):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.loginSucceededTitle,
                body: email.map {
                    MonitorText.LoginResultNotification.loginSucceededEmailBody($0)
                } ?? MonitorText.LoginResultNotification.loginSucceededBody
            )
        case .completed(.offline, _):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.offlineTitle,
                body: MonitorText.LoginResultNotification.offlineBody
            )
        case .completed(.cliMissing, _):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.cliMissingTitle,
                body: MonitorText.LoginResultNotification.cliMissingBody
            )
        case .completed(.serviceError, _):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.serviceErrorTitle,
                body: MonitorText.LoginResultNotification.serviceErrorBody
            )
        case .completed(.unauthenticated, _):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.stillUnauthenticatedTitle,
                body: MonitorText.LoginResultNotification.stillUnauthenticatedBody
            )
        case .completed(.checking, _):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.pendingTitle,
                body: MonitorText.LoginResultNotification.pendingBody
            )
        }
    }
}
