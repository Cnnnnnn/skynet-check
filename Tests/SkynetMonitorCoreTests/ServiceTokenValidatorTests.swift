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
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: StoreFakeNotifier(),
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

    @MainActor
    func testInvalidTokenNotifiesOnceUntilItTurnsValidAgain() async {
        let reader = StubTokenReader(tokens: [
            ServiceToken(key: "CONFLUENCE_TOKEN", displayName: "Confluence", value: "secret"),
        ])
        let validator = MutableTokenValidator()
        validator.outcome = .invalid
        let notifier = StoreFakeNotifier()
        let store = MonitorStore(
            checker: StoreFakeChecker(results: []),
            networkMonitor: StoreFakeNetworkMonitor(isAvailable: true),
            notifier: notifier,
            periodicInterval: nil,
            serviceTokenReader: reader,
            tokenValidator: validator
        )

        await store.inspectEnvironment()
        await store.inspectEnvironment()
        XCTAssertEqual(notifier.invalidTokenNotifications.count, 1)
        XCTAssertEqual(
            notifier.invalidTokenNotifications.first?.name,
            "Confluence"
        )

        validator.outcome = .valid
        await store.inspectEnvironment()
        validator.outcome = .invalid
        await store.inspectEnvironment()

        XCTAssertEqual(notifier.invalidTokenNotifications.count, 2)
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

    private final class MutableTokenValidator: ServiceTokenValidating, @unchecked Sendable {
        let supportedKeys: Set<String> = ["CONFLUENCE_TOKEN"]
        var outcome: ServiceTokenValidationOutcome = .valid

        func validate(token: ServiceToken) async -> ServiceTokenValidationOutcome {
            outcome
        }
    }
