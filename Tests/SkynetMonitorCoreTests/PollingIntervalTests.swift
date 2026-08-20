import XCTest
@testable import SkynetMonitorCore

final class PollingIntervalTests: XCTestCase {
    func testClampsValuesToThreeThroughSixtyMinutes() {
        XCTAssertEqual(PollingInterval.clamped(2), 3)
        XCTAssertEqual(PollingInterval.clamped(3), 3)
        XCTAssertEqual(PollingInterval.clamped(60), 60)
        XCTAssertEqual(PollingInterval.clamped(61), 60)
    }

    func testUsesFifteenMinutesAsTheDefault() {
        XCTAssertEqual(PollingInterval.defaultMinutes, 15)
    }

    func testPersistsAndLoadsTheSelectedInterval() {
        let suiteName = "PollingIntervalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = PollingInterval(defaults: defaults)

        settings.setMinutes(42)

        XCTAssertEqual(settings.minutes, 42)
        XCTAssertEqual(
            UserDefaults(suiteName: suiteName)?.integer(
                forKey: PollingInterval.storageKey
            ),
            42
        )
    }
}
