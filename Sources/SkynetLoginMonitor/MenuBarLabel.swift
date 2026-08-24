import AppKit
import SkynetMonitorCore
import SwiftUI

// Menu bar label: status icon plus an optional remaining-session countdown.
// The countdown only appears while authenticated with a live estimate and
// the user opted in; the icon alone carries the state the rest of the time.
@MainActor
struct MenuBarLabel: View {
    let state: LoginState
    let sessionExpiresAt: Date?
    let showCountdown: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(for: state))
                .accessibilityLabel(accessibilityText)
            if let countdown = countdownText {
                Text(countdown)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var countdownText: String? {
        guard showCountdown,
              state.isAuthenticated,
              let sessionExpiresAt
        else {
            return nil
        }
        return SessionExpiryPresentation.menuBarCountdown(
            expiresAt: sessionExpiresAt,
            now: now
        )
    }

    private var accessibilityText: String {
        guard let countdown = countdownText else {
            return state.presentation.title
        }
        return "\(state.presentation.title)，剩余 \(countdown)"
    }
}
