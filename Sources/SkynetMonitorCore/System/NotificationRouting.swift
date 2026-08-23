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
