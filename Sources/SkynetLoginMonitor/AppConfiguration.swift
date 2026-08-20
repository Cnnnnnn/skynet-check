import Foundation

enum AppConfiguration {
    // TODO: replace with the team's real manifest URL. It must serve JSON
    // like {"version": "0.3.0", "downloadUrl": "https://…/monitor.dmg"}.
    // Until then, "检查更新" reports a failure instead of false results.
    static let updateManifestURL = URL(
        string: "https://example.invalid/skynet-login-monitor/manifest.json"
    )!
}
