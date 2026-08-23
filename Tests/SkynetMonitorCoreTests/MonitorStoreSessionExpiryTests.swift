import XCTest
@testable import SkynetMonitorCore

@MainActor
final class MonitorStoreSessionExpiryTests: XCTestCase {
    func testRefreshNotifiesOnceWhenEstimatedExpiryApproaches() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let notifier = StoreFakeNotifier()
        // Past sessions lasted 2h; the current one started 90 minutes ago,
        // so the estimate sits 30 minutes out — inside the warning window.
        let expiryStore = StoreFakeSessionExpiryStore(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: now.addingTimeInterval(-5400),
                durations: [7200]
            )
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(
                results: [.authenticated(email: nil), .authenticated(email: nil)]
            ),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil,
            sessionExpiryStore: expiryStore,
            now: { now }
        )

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(notifier.expiringNotifications.count, 1)
        XCTAssertEqual(notifier.expiringNotifications.first?.stage, .warning)
        XCTAssertEqual(
            store.sessionExpiresAt,
            now.addingTimeInterval(1800)
        )
    }

    func testRefreshMarksOutlivedEstimateWhenPastHistoricalShortest() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.authenticated(email: nil)]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: StoreFakeSessionExpiryStore(
                record: SessionExpiryRecord(
                    lastAuthenticatedAt: now.addingTimeInterval(-5000),
                    durations: [3600]
                )
            ),
            now: { now }
        )

        await store.refresh()

        XCTAssertNil(store.sessionExpiresAt)
        XCTAssertTrue(store.sessionExpiryOutlived)
    }

    func testRefreshCapturesSessionDurationWhenExpiryDetected() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiryStore = StoreFakeSessionExpiryStore(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: now.addingTimeInterval(-3600),
                durations: []
            )
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(results: [.unauthenticated]),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: expiryStore,
            now: { now }
        )

        await store.refresh()

        XCTAssertEqual(expiryStore.saved?.durations, [3600])
        XCTAssertNil(store.sessionExpiresAt)
    }

    func testStatisticsPublishFromPersistedRecordOnInit() {
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: StoreFakeSessionExpiryStore(
                record: SessionExpiryRecord(durations: [3600, 7200])
            )
        )

        XCTAssertEqual(store.sessionStatistics?.observationCount, 2)
        XCTAssertEqual(store.sessionStatistics?.average ?? 0, 5400, accuracy: 1)
    }

    func testResetSessionStatisticsClearsDurationsButKeepsCurrentSession() {
        let expiryStore = StoreFakeSessionExpiryStore(
            record: SessionExpiryRecord(
                lastAuthenticatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                durations: [3600, 7200]
            )
        )
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
            periodicInterval: nil,
            sessionExpiryStore: expiryStore
        )

        store.resetSessionStatistics()

        XCTAssertNil(store.sessionStatistics)
        XCTAssertNil(store.sessionExpiresAt)
        XCTAssertEqual(
            expiryStore.saved?.lastAuthenticatedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(expiryStore.saved?.durations, [])
    }
}
