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

@MainActor
public protocol LoginNotifying: AnyObject {
    func requestAuthorization() async
    func notifyLoginExpired() async
    func notifyCheckResult(_ state: LoginState) async
}

@MainActor
public final class LoginNotifier: NSObject, LoginNotifying,
    UNUserNotificationCenterDelegate
{
    private static let identifier = "skynet-login-expired"
    private let bundle: Bundle
    private let centerProvider: @MainActor () -> UNUserNotificationCenter

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
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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

        let request = UNNotificationRequest(
            identifier: "skynet-manual-check-\(UUID().uuidString)",
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
