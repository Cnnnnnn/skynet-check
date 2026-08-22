import Foundation
import UserNotifications

enum NotificationEnvironment {
    static func supportsUserNotifications(
        bundleURL: URL,
        bundleIdentifier: String?
    ) -> Bool {
        bundleURL.pathExtension.lowercased() == "app"
            && bundleIdentifier?.isEmpty == false
    }
}

enum NotificationPresentationPolicy {
    static let foregroundOptions: UNNotificationPresentationOptions = [
        .banner,
        .sound,
    ]
}

public enum NotificationPermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case unsupported

    var logLabel: String {
        switch self {
        case .authorized:
            "authorized"
        case .notDetermined:
            "notDetermined"
        case .denied:
            "denied"
        case .unsupported:
            "unsupported"
        }
    }
}

public extension NotificationPermissionStatus {
    // Hidden when the runtime cannot show notifications at all (e.g. a bare
    // executable run outside an app bundle).
    var shouldShowInPanel: Bool {
        self != .unsupported
    }

    var needsSettingsShortcut: Bool {
        self == .denied
    }
}

enum NotificationPermissionMapper {
    static func status(
        from authorizationStatus: UNAuthorizationStatus
    ) -> NotificationPermissionStatus {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

// Pure routing rules, kept outside the @MainActor class so the
// nonisolated notification delegate can use them directly.
enum NotificationActionRouting {
    static let actionCategory = "skynet-login-actions"
    static let manualCheckIdentifier = "skynet-manual-check"

    // Action-category notifications (login expired / expiring, manual
    // unauthenticated checks) default to re-login; other manual results
    // default to a fresh check. Token notifications have no safe action.
    static func defaultAction(
        categoryIdentifier: String,
        identifier: String
    ) -> LoginNotificationAction? {
        if categoryIdentifier == actionCategory {
            return .login
        }
        if identifier == manualCheckIdentifier {
            return .check
        }
        return nil
    }
}

@MainActor
public protocol LoginNotifying: AnyObject {
    func requestAuthorization() async
    func authorizationStatus() async -> NotificationPermissionStatus
    func notifyLoginExpired() async
    func notifySessionExpiring(
        stage: SessionExpiryAdvisor.Stage,
        expiresAt: Date
    ) async
    func notifyServiceTokenInvalid(key: String, name: String) async
    func notifyCheckResult(_ state: LoginState) async
    func notifyLoginResult(_ result: LoginActionResult) async
    func notifyComponentUpdatesAvailable(skillCount: Int, mcpCount: Int) async
}

public extension LoginNotifying {
    // Test doubles stay quiet unless they care about this event.
    func notifyComponentUpdatesAvailable(skillCount: Int, mcpCount: Int) async {}
}

@MainActor
public final class LoginNotifier: NSObject, LoginNotifying,
    UNUserNotificationCenterDelegate
{
    private static let identifier = "skynet-login-expired"
    private static let expiringIdentifier = "skynet-session-expiring"
    private static let tokenInvalidPrefix = "skynet-token-invalid"
    private static let loginActionIdentifier = "skynet-login-action"
    private static let componentUpdatesIdentifier = "skynet-component-updates"
    private let bundle: Bundle
    private let centerProvider: @MainActor () -> UNUserNotificationCenter
    public var onAction: (@MainActor (LoginNotificationAction) -> Void)?

    public init(
        bundle: Bundle = .main,
        centerProvider: @escaping @MainActor () -> UNUserNotificationCenter = {
            .current()
        }
    ) {
        self.bundle = bundle
        self.centerProvider = centerProvider
        super.init()
    }

    public func requestAuthorization() async {
        guard supportsUserNotifications else {
            return
        }
        let center = configuredCenter()
        let actions = [
            UNNotificationAction(
                identifier: LoginNotificationAction.login.rawValue,
                title: MonitorText.NotificationAction.login,
                options: [.foreground]
            ),
            UNNotificationAction(
                identifier: LoginNotificationAction.check.rawValue,
                title: MonitorText.NotificationAction.check,
                options: []
            ),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationActionRouting.actionCategory,
                actions: actions,
                intentIdentifiers: [],
                options: []
            ),
        ])
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound]
            )
            MonitorLog.notifier.info(
                "notification authorization granted=\(granted, privacy: .public)"
            )
        } catch {
            MonitorLog.notifier.error(
                "notification authorization failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func authorizationStatus() async -> NotificationPermissionStatus {
        guard supportsUserNotifications else {
            return .unsupported
        }
        let settings = await configuredCenter().notificationSettings()
        let status = NotificationPermissionMapper.status(
            from: settings.authorizationStatus
        )
        MonitorLog.notifier.info(
            "notification authorization status: \(status.logLabel, privacy: .public)"
        )
        return status
    }

    public func notifyLoginExpired() async {
        guard supportsUserNotifications else {
            return
        }
        let center = configuredCenter()
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.identifier]
        )

        let content = UNMutableNotificationContent()
        content.title = MonitorText.ExpiredNotification.title
        content.body = MonitorText.ExpiredNotification.body
        content.sound = .default
        content.categoryIdentifier = NotificationActionRouting.actionCategory

        await post(
            UNNotificationRequest(
                identifier: Self.identifier,
                content: content,
                trigger: nil
            ),
            label: "login-expired"
        )
    }

    public func notifySessionExpiring(
        stage: SessionExpiryAdvisor.Stage,
        expiresAt: Date
    ) async {
        guard supportsUserNotifications else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = MonitorText.ExpiringNotification.title(stage: stage)
        content.body = MonitorText.ExpiringNotification.body(
            stage: stage,
            expiresAt: expiresAt
        )
        content.sound = .default
        content.categoryIdentifier = NotificationActionRouting.actionCategory
        content.userInfo = [
            "stage": stage.rawValue,
        ]

        await post(
            UNNotificationRequest(
                identifier: Self.expiringIdentifier,
                content: content,
                trigger: nil
            ),
            label: "session-expiring-\(stage.logLabel)"
        )
    }

    public func notifyServiceTokenInvalid(key: String, name: String) async {
        guard supportsUserNotifications else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = MonitorText.ServiceToken.invalidNotificationTitle(name: name)
        content.body = MonitorText.ServiceToken.invalidNotificationBody
        content.sound = .default

        await post(
            UNNotificationRequest(
                identifier: "\(Self.tokenInvalidPrefix)-\(key)",
                content: content,
                trigger: nil
            ),
            label: "token-invalid"
        )
    }

    public func notifyCheckResult(_ state: LoginState) async {
        guard supportsUserNotifications,
              let notification = state.manualCheckNotification
        else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        if state == .unauthenticated {
            content.categoryIdentifier = NotificationActionRouting.actionCategory
        }

        // A stable identifier replaces the previous delivered notification
        // instead of piling up history in Notification Center.
        await post(
            UNNotificationRequest(
                identifier: NotificationActionRouting.manualCheckIdentifier,
                content: content,
                trigger: nil
            ),
            label: "manual-check"
        )
    }

    public func notifyLoginResult(_ result: LoginActionResult) async {
        guard supportsUserNotifications else {
            return
        }
        let notification = result.notification
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        await post(
            UNNotificationRequest(
                identifier: Self.loginActionIdentifier,
                content: content,
                trigger: nil
            ),
            label: "login-action"
        )
    }

    public func notifyComponentUpdatesAvailable(
        skillCount: Int,
        mcpCount: Int
    ) async {
        guard supportsUserNotifications else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = MonitorText.ComponentUpdate.updatesNotificationTitle
        content.body = MonitorText.ComponentUpdate.updatesNotificationBody(
            skillCount: skillCount,
            mcpCount: mcpCount
        )
        content.sound = .default

        await post(
            UNNotificationRequest(
                identifier: Self.componentUpdatesIdentifier,
                content: content,
                trigger: nil
            ),
            label: "component-updates"
        )
    }

    private func post(
        _ request: UNNotificationRequest,
        label: String
    ) async {
        let center = centerProvider()
        do {
            try await center.add(request)
            MonitorLog.notifier.info(
                "posted \(label, privacy: .public) notification"
            )
        } catch {
            MonitorLog.notifier.error(
                "failed to post \(label, privacy: .public) notification: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        NotificationPresentationPolicy.foregroundOptions
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action: LoginNotificationAction?
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // Tapping the notification body itself should do the most
            // useful thing for that notification type.
            action = NotificationActionRouting.defaultAction(
                categoryIdentifier: response.notification.request.content
                    .categoryIdentifier,
                identifier: response.notification.request.identifier
            )
        } else {
            action = LoginNotificationAction(
                rawValue: response.actionIdentifier
            )
        }
        guard let action else {
            return
        }
        await MainActor.run { [weak self] in
            self?.onAction?(action)
        }
    }

    private var supportsUserNotifications: Bool {
        NotificationEnvironment.supportsUserNotifications(
            bundleURL: bundle.bundleURL,
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    private func configuredCenter() -> UNUserNotificationCenter {
        let center = centerProvider()
        center.delegate = self
        return center
    }
}
