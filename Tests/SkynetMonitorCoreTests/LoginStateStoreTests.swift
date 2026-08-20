import Foundation
import XCTest
@testable import SkynetMonitorCore

final class LoginStateStoreTests: XCTestCase {
    func testRoundTripsSnapshotThroughDefaults() {
        let suiteName = makeSuiteName()
        let store = LoginStateStore(defaults: UserDefaults(suiteName: suiteName)!)
        let snapshot = LoginStateSnapshot(
            state: .authenticated(email: "user@example.com"),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    func testRoundTripsServiceErrorDetail() {
        let suiteName = makeSuiteName()
        let store = LoginStateStore(defaults: UserDefaults(suiteName: suiteName)!)
        let snapshot = LoginStateSnapshot(
            state: .serviceError(message: "connection reset"),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    func testReturnsNilForCorruptedData() {
        let suiteName = makeSuiteName()
        UserDefaults(suiteName: suiteName)!.set(
            Data([0x00, 0x01]),
            forKey: "lastLoginStateSnapshot"
        )
        let store = LoginStateStore(defaults: UserDefaults(suiteName: suiteName)!)

        XCTAssertNil(store.load())
    }

    private func makeSuiteName() -> String {
        let suiteName = "LoginStateStoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return suiteName
    }
}
