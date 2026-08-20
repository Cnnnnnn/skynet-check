import Foundation
import XCTest
@testable import SkynetMonitorCore

final class ServiceTokenValidatorTests: XCTestCase {
    func testKnownUserMeansValid() {
        let body = #"{"type":"known","username":"user@example.com"}"#

        XCTAssertEqual(
            ConfluenceTokenValidator.outcome(
                statusCode: 200,
                body: Data(body.utf8)
            ),
            .valid
        )
    }

    func testAnonymousUserMeansInvalid() {
        let body = #"{"type":"anonymous","displayName":"Anonymous"}"#

        XCTAssertEqual(
            ConfluenceTokenValidator.outcome(
                statusCode: 200,
                body: Data(body.utf8)
            ),
            .invalid
        )
        XCTAssertEqual(
            ConfluenceTokenValidator.outcome(
                statusCode: 401,
                body: Data()
            ),
            .invalid
        )
    }

    func testUnexpectedResponsesStayUnknown() {
        XCTAssertEqual(
            ConfluenceTokenValidator.outcome(statusCode: 500, body: Data()),
            .unknown
        )
        XCTAssertEqual(
            ConfluenceTokenValidator.outcome(
                statusCode: 200,
                body: Data("not json".utf8)
            ),
            .unknown
        )
        XCTAssertEqual(
            ConfluenceTokenValidator.outcome(statusCode: nil, body: Data()),
            .unknown
        )
    }

    func testValidatorOnlyHandlesConfluenceKey() async {
        let validator = ConfluenceTokenValidator()
        let otherToken = ServiceToken(
            key: "JIRA_TOKEN",
            displayName: "Jira",
            value: "anything"
        )

        let outcome = await validator.validate(token: otherToken)

        XCTAssertEqual(outcome, .unknown)
        XCTAssertTrue(validator.supportedKeys.contains("CONFLUENCE_TOKEN"))
    }

    @MainActor
    func testInspectEnvironmentRecordsTokenValidation() async {
        let reader = StubTokenReader(tokens: [
            ServiceToken(key: "CONFLUENCE_TOKEN", displayName: "Confluence", value: "secret"),
        ])
        let store = MonitorStore(
            checker: StubChecker(),
            networkMonitor: StubNetworkMonitor(),
            notifier: StubNotifier(),
            periodicInterval: nil,
            serviceTokenReader: reader,
            tokenValidator: StubTokenValidator(outcome: .invalid)
        )

        await store.inspectEnvironment()

        XCTAssertEqual(
            store.tokenValidation["CONFLUENCE_TOKEN"],
            .invalid
        )
    }

    func testDiagnosticsIncludeTokenValidationVerdict() {
        let report = DiagnosticsComposer.compose(
            appVersion: "0.4.0",
            state: nil,
            lastCheckedAt: nil,
            lastCompletedState: nil,
            sessionExpiresAt: nil,
            pollingIntervalMinutes: 15,
            notificationPermission: .authorized,
            permissionAudit: nil,
            environment: nil,
            tokenValidation: ["CONFLUENCE_TOKEN": .invalid]
        )

        XCTAssertTrue(report.contains("- Token CONFLUENCE_TOKEN：已失效"))
    }
}

private struct StubTokenReader: ServiceTokenReading {
    let tokens: [ServiceToken]

    func availableTokens() -> [ServiceToken] {
        tokens
    }
}

private struct StubTokenValidator: ServiceTokenValidating {
    let supportedKeys: Set<String> = ["CONFLUENCE_TOKEN"]
    let outcome: ServiceTokenValidationOutcome

    func validate(token: ServiceToken) async -> ServiceTokenValidationOutcome {
        outcome
    }
}

private struct StubChecker: SkynetAuthChecking {
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
private final class StubNetworkMonitor: NetworkMonitoring {
    var isAvailable = true

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) async {}

    func stop() {}
}

@MainActor
private final class StubNotifier: LoginNotifying {
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
