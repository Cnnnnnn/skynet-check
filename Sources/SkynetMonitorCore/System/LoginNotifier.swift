import Foundation
import UserNotifications

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
    // When set (and in the future), notifications are dropped instead of
    // posted; checks and panel updates continue as normal. The store also
    // counts suppressions so the first post-mute notification can carry a
    // "已抑制 N 条" summary.
    public var muteProvider: @MainActor () -> NotificationMuteWindow?
    public weak var muteStore: NotificationMuteStore?
    public var now: @MainActor () -> Date
    public var onAction: (@MainActor (LoginNotificationAction) -> Void)?

    public init(
        bundle: Bundle = .main,
        centerProvider: @escaping @MainActor () -> UNUserNotificationCenter = {
            .current()
        },
        muteProvider: @escaping @MainActor () -> NotificationMuteWindow? = { nil },
        muteStore: NotificationMuteStore? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.bundle = bundle
        self.centerProvider = centerProvider
        self.muteProvider = muteProvider
        self.muteStore = muteStore
        self.now = now
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
        if NotificationMuteWindow.isActive(muteProvider(), now: now()) {
            muteStore?.recordSuppressed()
            MonitorLog.notifier.info(
                "muted \(label, privacy: .public) notification (do-not-disturb)"
            )
            return
        }
        // The first notification after a mute episode ends carries how many
        // were suppressed, so nothing silently vanished.
        if let muteStore, let count = muteStore.takeSuppressionSummary(now: now()) {
            let annotated = UNMutableNotificationContent()
            annotated.title = request.content.title
            annotated.body = "（勿扰期间已抑制 \(count) 条通知）\n" + request.content.body
            annotated.sound = request.content.sound
            annotated.userInfo = request.content.userInfo
            annotated.categoryIdentifier = request.content.categoryIdentifier
            await deliver(
                UNNotificationRequest(
                    identifier: request.identifier,
                    content: annotated,
                    trigger: nil
                ),
                label: label
            )
            return
        }
        await deliver(request, label: label)
    }

    private func deliver(
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
            let message = "failed to post \(label) notification: \(error.localizedDescription)"
            MonitorLog.notifier.error("\(message, privacy: .public)")
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
