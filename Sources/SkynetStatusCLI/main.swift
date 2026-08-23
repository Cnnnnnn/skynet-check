import Foundation
import SkynetMonitorCore

// Thin I/O shell around StatusReport: reads the snapshots the running app
// persists and prints one JSON document.

@main
struct StatusCommand {
    static func main() {
        // The app persists its snapshots under its own bundle identifier's
        // defaults domain; reading .standard here would see a different,
        // empty store. A bare swift-build binary has no Info.plist, so it
        // falls back to the packaged app's known bundle ID.
        let bundleID = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleIdentifier"
        ) as? String
        let domain: String
        switch bundleID {
        case .none, .some("SkynetLoginMonitor"), .some(""):
            domain = "io.skynet.login-monitor"
        case .some(let id):
            domain = id
        }
        guard let defaults = UserDefaults(suiteName: domain) else {
            fail("cannot open defaults suite \(domain)")
        }

        guard let snapshot = LoginStateStore(defaults: defaults).load() else {
            FileHandle.standardError.write(Data(
                "skynet-status error: no status yet — has the app completed a check?\n".utf8
            ))
            exit(1)
        }

        let expiryRecord = SessionExpiryStore(defaults: defaults).load()
        let report = StatusReport.make(
            snapshot: snapshot,
            expiryRecord: expiryRecord,
            now: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("skynet-status error: \(message)\n".utf8))
        exit(2)
    }
}
