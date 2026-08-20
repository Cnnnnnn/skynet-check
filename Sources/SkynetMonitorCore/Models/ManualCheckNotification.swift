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
                title: MonitorText.ManualCheckNotification.authenticatedTitle,
                body: email.map {
                    MonitorText.ManualCheckNotification.authenticatedEmailBody($0)
                } ?? MonitorText.ManualCheckNotification.authenticatedBody
            )
        case .unauthenticated:
            ManualCheckNotification(
                title: MonitorText.ManualCheckNotification.unauthenticatedTitle,
                body: MonitorText.ManualCheckNotification.unauthenticatedBody
            )
        case .offline:
            ManualCheckNotification(
                title: MonitorText.ManualCheckNotification.offlineTitle,
                body: MonitorText.ManualCheckNotification.offlineBody
            )
        case .serviceError:
            ManualCheckNotification(
                title: MonitorText.ManualCheckNotification.serviceErrorTitle,
                body: MonitorText.ManualCheckNotification.serviceErrorBody
            )
        case .cliMissing:
            ManualCheckNotification(
                title: MonitorText.ManualCheckNotification.cliMissingTitle,
                body: MonitorText.ManualCheckNotification.cliMissingBody
            )
        }
    }
}
