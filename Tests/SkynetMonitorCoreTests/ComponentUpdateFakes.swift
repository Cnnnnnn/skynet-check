import Foundation
import XCTest
@testable import SkynetMonitorCore

final class StubPlatformClient: SkynetSkillVersionFetching, @unchecked Sendable {
    let token: String?
    var batch: [String: String]
    var latest: [String: String]
    var batchFails = false
    var failingSkills: Set<String> = []

    init(
        token: String?,
        latest: [String: String],
        batch: [String: String] = [:]
    ) {
        self.token = token
        self.latest = latest
        self.batch = batch
    }

    func sessionToken() async -> String? {
        token
    }

    func latestMainVersions() async throws -> [String: String] {
        if batchFails {
            throw HTTPSkynetPlatformClient.ClientError.apiRejected
        }
        return batch
    }

    func latestMainVersion(for skillName: String) async throws -> String? {
        if failingSkills.contains(skillName) {
            throw HTTPSkynetPlatformClient.ClientError.apiRejected
        }
        return latest[skillName]
    }
}

final class StubRegistry: NpmRegistryLatestFetching, @unchecked Sendable {
    let versions: [String: String]

    init(versions: [String: String]) {
        self.versions = versions
    }

    func latestVersion(of package: String) async -> String? {
        versions[package]
    }
}

final class MutableSkillUpdateChecker: SkillUpdateChecking, @unchecked Sendable {
    var result: SkillUpdateCheckResult = .failed(reason: nil)
    private(set) var callCount = 0

    func checkForUpdates() async -> SkillUpdateCheckResult {
        callCount += 1
        return result
    }
}

final class MutableMcpVersionChecker: McpVersionChecking, @unchecked Sendable {
    var findings: [McpVersionFinding] = []

    func checkVersions() async -> [McpVersionFinding] {
        findings
    }
}

struct StubChecker: SkynetAuthChecking {
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
final class StubNetworkMonitor: NetworkMonitoring {
    var isAvailable = true

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) async {}

    func stop() {}
}

@MainActor
final class StubNotifier: LoginNotifying {
    private(set) var componentUpdateNotifications: [(skillCount: Int, mcpCount: Int)] = []

    func requestAuthorization() async {}

    func authorizationStatus() async -> NotificationPermissionStatus {
        .authorized
    }

    func notifyLoginExpired() async {}

    func notifySessionExpiring(
        stage: SessionExpiryAdvisor.Stage,
        expiresAt: Date
    ) async {}

    func notifyServiceTokenInvalid(key: String, name: String) async {}

    func notifyCheckResult(_ state: LoginState) async {}

    func notifyLoginResult(_ result: LoginActionResult) async {}

    func notifyComponentUpdatesAvailable(skillCount: Int, mcpCount: Int) async {
        componentUpdateNotifications.append((skillCount, mcpCount))
    }
}
