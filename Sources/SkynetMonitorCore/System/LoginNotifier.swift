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

@MainActor
public protocol LoginNotifying: AnyObject {
    func requestAuthorization() async
    func authorizationStatus() async -> NotificationPermissionStatus
    func notifyLoginExpired() async
    func notifyCheckResult(_ state: LoginState) async
    func notifyLoginResult(_ result: LoginActionResult) async
}

@MainActor
public final class LoginNotifier: NSObject, LoginNotifying,
    UNUserNotificationCenterDelegate
{
    private static let identifier = "skynet-login-expired"
    private static let actionCategory = "skynet-login-actions"
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
                title: "重新登录",
                options: [.foreground]
            ),
            UNNotificationAction(
                identifier: LoginNotificationAction.check.rawValue,
                title: "立即检查",
                options: []
            ),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.actionCategory,
                actions: actions,
                intentIdentifiers: [],
                options: []
            ),
        ])
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func authorizationStatus() async -> NotificationPermissionStatus {
        guard supportsUserNotifications else {
            return .unsupported
        }
        let settings = await configuredCenter().notificationSettings()
        return NotificationPermissionMapper.status(
            from: settings.authorizationStatus
        )
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
        content.title = "Skynet 登录已失效"
        content.body = "请重新登录，以免 CLI 任务执行时中断。"
        content.sound = .default
        content.categoryIdentifier = Self.actionCategory

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    public func notifyCheckResult(_ state: LoginState) async {
        guard supportsUserNotifications,
              let notification = state.manualCheckNotification
        else {
            return
        }
        let center = configuredCenter()
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        if state == .unauthenticated {
            content.categoryIdentifier = Self.actionCategory
        }

        let request = UNNotificationRequest(
            identifier: "skynet-manual-check-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    public func notifyLoginResult(_ result: LoginActionResult) async {
        guard supportsUserNotifications else {
            return
        }
        let center = configuredCenter()
        let notification = result.notification
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "skynet-login-action-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
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
        guard let action = LoginNotificationAction(
            rawValue: response.actionIdentifier
        ) else {
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
