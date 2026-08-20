import UserNotifications

@MainActor
public protocol LoginNotifying: AnyObject {
    func requestAuthorization() async
    func notifyLoginExpired() async
}

@MainActor
public final class LoginNotifier: LoginNotifying {
    private static let identifier = "skynet-login-expired"
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func notifyLoginExpired() async {
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
}
