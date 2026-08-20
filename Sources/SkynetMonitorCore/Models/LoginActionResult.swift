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
                title: MonitorText.LoginResultNotification.alreadyAuthenticatedTitle,
                body: email.map {
                    MonitorText.LoginResultNotification.alreadyAuthenticatedBody($0)
                } ?? MonitorText.LoginResultNotification.alreadyAuthenticatedBodyFallback
            )
        case let .completed(.authenticated(email)):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.loginSucceededTitle,
                body: email.map {
                    MonitorText.LoginResultNotification.loginSucceededEmailBody($0)
                } ?? MonitorText.LoginResultNotification.loginSucceededBody
            )
        case .completed(.offline):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.offlineTitle,
                body: MonitorText.LoginResultNotification.offlineBody
            )
        case .completed(.cliMissing):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.cliMissingTitle,
                body: MonitorText.LoginResultNotification.cliMissingBody
            )
        case .completed(.serviceError):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.serviceErrorTitle,
                body: MonitorText.LoginResultNotification.serviceErrorBody
            )
        case .completed(.unauthenticated):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.stillUnauthenticatedTitle,
                body: MonitorText.LoginResultNotification.stillUnauthenticatedBody
            )
        case .completed(.checking):
            ManualCheckNotification(
                title: MonitorText.LoginResultNotification.pendingTitle,
                body: MonitorText.LoginResultNotification.pendingBody
            )
        }
    }
}
