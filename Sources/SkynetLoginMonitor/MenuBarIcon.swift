import AppKit
import SkynetMonitorCore

@MainActor
enum MenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for state: LoginState) -> NSImage {
        let key = state.presentation.title
        if let cached = cache[key] {
            return cached
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        switch state {
        case .checking:
            fillCircle(center: 9, radius: 3, color: .systemGray)
        case .authenticated:
            fillCircle(center: 9, radius: 6, color: .systemGreen)
        case .unauthenticated:
            strokeCircle(center: 9, radius: 5, color: .systemRed, lineWidth: 3.5)
        case .offline, .serviceError:
            strokeCircle(center: 9, radius: 6, color: .systemYellow, lineWidth: 2.5)
        case .cliMissing:
            strokeCircle(center: 9, radius: 6, color: .systemGray, lineWidth: 2)
        }
        image.unlockFocus()

        // The menu bar renders template images in monochrome; only a
        // non-template image keeps the status color visible.
        image.isTemplate = false
        cache[key] = image
        return image
    }

    private static func fillCircle(
        center: CGFloat,
        radius: CGFloat,
        color: NSColor
    ) {
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center - radius,
                y: center - radius,
                width: radius * 2,
                height: radius * 2
            )
        ).fill()
    }

    private static func strokeCircle(
        center: CGFloat,
        radius: CGFloat,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        color.setStroke()
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: center - radius,
                y: center - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        path.lineWidth = lineWidth
        path.stroke()
    }
}
