import Foundation
import SkynetMonitorCore

// Thin I/O shell around StatusReport: reads the snapshots the running app
// persists and prints one JSON document.

@main
struct StatusCommand {
    static func main() {
        // The app persists snapshots under its bundle identifier's defaults
        // domain. Three run contexts:
        // - inside the packaged app: Bundle.main carries its identifier and
        //   .standard already IS that domain (a suite of the same name is
        //   rejected by macOS);
        // - bare binary: no Info.plist, open the app's domain as an
        //   explicit suite;
        // - any other host bundle: read that bundle's own domain.
        let bundleID = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleIdentifier"
        ) as? String
        let appDomain = "io.skynet.login-monitor"
        let defaults: UserDefaults
        switch bundleID {
        case .some(appDomain):
            defaults = .standard
        case .none, .some("SkynetLoginMonitor"), .some("skynet-status"), .some(""):
            guard let suite = UserDefaults(suiteName: appDomain) else {
                fail("cannot open defaults suite \(appDomain)")
            }
            defaults = suite
        case .some(let id):
            guard let suite = UserDefaults(suiteName: id) else {
                fail("cannot open defaults suite \(id)")
            }
            defaults = suite
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
