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

@MainActor
public protocol LoginNotifying: AnyObject {
    func requestAuthorization() async
    func notifyLoginExpired() async
}

@MainActor
public final class LoginNotifier: LoginNotifying {
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
    }

    public func requestAuthorization() async {
        guard supportsUserNotifications else {
            return
        }
        let center = centerProvider()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func notifyLoginExpired() async {
        guard supportsUserNotifications else {
            return
        }
        let center = centerProvider()
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

    private var supportsUserNotifications: Bool {
        NotificationEnvironment.supportsUserNotifications(
            bundleURL: bundle.bundleURL,
            bundleIdentifier: bundle.bundleIdentifier
        )
    }
}
