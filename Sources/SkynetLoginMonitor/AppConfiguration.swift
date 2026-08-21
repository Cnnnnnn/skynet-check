import Foundation

enum AppConfiguration {
    // TODO: replace with the team's real manifest URL. It must serve JSON
    // like {"version": "0.3.0", "downloadUrl": "https://…/monitor.dmg"}.
    // While nil the panel hides the "检查更新" row instead of offering a
    // check that can only fail.
    static let updateManifestURL: URL? = nil
}
