import Foundation
import XCTest
@testable import SkynetMonitorCore

final class ServiceTokenStoreTests: XCTestCase {
    func testLoadsTokensWithDisplayNamesAndSortedKeys() throws {
        let url = try writeTemporaryTokens(
            #"{"CONFLUENCE_TOKEN": "abcd1234efgh5678ijkl", "JIRA_TOKEN": "jira-secret-value-123"}"#
        )
        let store = ServiceTokenStore(tokensURL: url)

        let tokens = store.availableTokens()

        XCTAssertEqual(tokens.map(\.key), ["CONFLUENCE_TOKEN", "JIRA_TOKEN"])
        XCTAssertEqual(tokens.first?.displayName, "Confluence")
        XCTAssertEqual(tokens.last?.displayName, "JIRA_TOKEN")
    }

    func testSkipsEmptyValuesAndMissingFile() throws {
        let url = try writeTemporaryTokens(#"{"CONFLUENCE_TOKEN": ""}"#)
        let store = ServiceTokenStore(tokensURL: url)

        XCTAssertTrue(store.availableTokens().isEmpty)

        let missing = ServiceTokenStore(
            tokensURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("no-such-tokens-\(UUID().uuidString).json")
        )
        XCTAssertTrue(missing.availableTokens().isEmpty)
    }

    func testMasksValueForDisplay() {
        let longToken = ServiceToken(
            key: "CONFLUENCE_TOKEN",
            displayName: "Confluence",
            value: "sk-d7ea9f2a"
        )
        let shortToken = ServiceToken(
            key: "SHORT",
            displayName: "Short",
            value: "abc"
        )

        XCTAssertEqual(longToken.maskedValue, "sk-d…9f2a")
        XCTAssertEqual(shortToken.maskedValue, "••••")
    }

    @MainActor
    func testInspectEnvironmentPublishesServiceTokens() async {
        let reader = FakeServiceTokenReader(tokens: [
            ServiceToken(
                key: "CONFLUENCE_TOKEN",
                displayName: "Confluence",
                value: "secret"
            ),
        ])
        let store = MonitorStore(
            checker: FakeChecker(),
            networkMonitor: FakeNetworkMonitor(),
            notifier: FakeNotifier(),
            periodicInterval: nil,
            serviceTokenReader: reader
        )

        await store.inspectEnvironment()

        XCTAssertEqual(store.serviceTokens.count, 1)
        XCTAssertEqual(store.serviceTokens.first?.displayName, "Confluence")
    }

    private func writeTemporaryTokens(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokens-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct FakeServiceTokenReader: ServiceTokenReading {
    let tokens: [ServiceToken]

    func availableTokens() -> [ServiceToken] {
        tokens
    }
}

private struct FakeChecker: SkynetAuthChecking {
    func check(networkAvailable: Bool) async -> LoginState {
        .authenticated(email: nil)
    }

    func login(networkAvailable: Bool) async -> LoginActionResult {
        .alreadyAuthenticated(email: nil)
    }

    func version() async -> String? {
        nil
    }
}

@MainActor
private final class FakeNetworkMonitor: NetworkMonitoring {
    var isAvailable = true

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) async {}

    func stop() {}
}

@MainActor
private final class FakeNotifier: LoginNotifying {
    func requestAuthorization() async {}

    func authorizationStatus() async -> NotificationPermissionStatus {
        .authorized
    }

    func notifyLoginExpired() async {}

    func notifySessionExpiring(
        stage: SessionExpiryAdvisor.Stage,
        expiresAt: Date
    ) async {}

    func notifyCheckResult(_ state: LoginState) async {}

    func notifyLoginResult(_ result: LoginActionResult) async {}
}
