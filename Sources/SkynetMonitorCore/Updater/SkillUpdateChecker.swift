import Foundation

public struct SkillUpdate: Codable, Equatable, Sendable {
    public let name: String
    public let installedVersion: String
    public let latestVersion: String

    public init(name: String, installedVersion: String, latestVersion: String) {
        self.name = name
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
    }
}

public struct SkillUpdateReport: Codable, Equatable, Sendable {
    public let totalChecked: Int
    public let updates: [SkillUpdate]

    public init(totalChecked: Int, updates: [SkillUpdate]) {
        self.totalChecked = totalChecked
        self.updates = updates
    }
}

public enum SkillUpdateCheckResult: Equatable, Sendable {
    case needsLogin
    case completed(SkillUpdateReport)
    // nil reason keeps "failed" usable without a diagnosis.
    case failed(reason: String?)

    var logLabel: String {
        switch self {
        case .needsLogin:
            "needs login"
        case let .completed(report):
            "completed, \(report.updates.count) of \(report.totalChecked) upgradable"
        case let .failed(reason):
            "failed (\(reason ?? "unknown"))"
        }
    }
}

// Panel-facing phase for the component-version card; the detailed lists are
// carried by the separate published findings.
public enum ComponentUpdatePhase: Codable, Equatable, Sendable {
    case idle
    case checking
    case needsLogin
    case completed
    case failed
}

public protocol SkillUpdateChecking: Sendable {
    func checkForUpdates() async -> SkillUpdateCheckResult
}

// Talks to the Skynet platform skill API. A skill's "latest" is its main
// version (`main_version_number`), matching what `skynet skill install
// <name>@latest` resolves to on the CLI. The list endpoint is paginated
// (page_size up to 500) and carries the same version field per entry, so
// bulk checks page through it instead of one detail call per skill.
public protocol SkynetSkillVersionFetching: Sendable {
    func sessionToken() async -> String?
    func latestMainVersions() async throws -> [String: String]
    func latestMainVersion(for skillName: String) async throws -> String?
}

public actor HTTPSkynetPlatformClient: SkynetSkillVersionFetching {
    public enum ClientError: Error, Equatable {
        case apiRejected
        case malformedResponse
    }

    private let sessionURL: URL
    private let apiBase: URL
    private let session: URLSession

    public init(
        sessionURL: URL = SkynetEndpoints.homeRelative(SkynetEndpoints.sessionPath),
        apiBase: URL = URL(string: SkynetEndpoints.skillPlatformBase)!,
        session: URLSession = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            return configuration
        }())
    ) {
        self.sessionURL = sessionURL
        self.apiBase = apiBase
        self.session = session
    }

    public func sessionToken() -> String? {
        guard let data = try? Data(contentsOf: sessionURL) else {
            return nil
        }
        return Self.parseSessionToken(from: data)
    }

    public func latestMainVersion(for skillName: String) async throws -> String? {
        guard var components = URLComponents(
            url: apiBase,
            resolvingAgainstBaseURL: false
        ) else {
            throw ClientError.malformedResponse
        }
        components.path = "/api/platform/agent_skill/v1/detail"
        components.queryItems = [URLQueryItem(name: "skill_name", value: skillName)]
        guard let url = components.url else {
            throw ClientError.malformedResponse
        }
        let data = try await get(url)
        return try Self.parseDetailResponse(from: data)
    }

    public func latestMainVersions() async throws -> [String: String] {
        var versions: [String: String] = [:]
        var page = 1
        let pageSize = 500
        let maxPages = 10
        while page <= maxPages {
            guard var components = URLComponents(
                url: apiBase,
                resolvingAgainstBaseURL: false
            ) else {
                throw ClientError.malformedResponse
            }
            components.path = "/api/platform/agent_skill/v1/list"
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
            guard let url = components.url else {
                throw ClientError.malformedResponse
            }
            let result = try Self.parseListPage(from: try await get(url))
            versions.merge(result.versions) { current, _ in current }
            if versions.count >= result.total || result.returned < pageSize {
                break
            }
            page += 1
        }
        return versions
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        if let token = sessionToken() {
            request.setValue(
                "SPC_CS_SKYNET=\(token)",
                forHTTPHeaderField: "Cookie"
            )
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    static func parseSessionToken(from data: Data) -> String? {
        struct Session: Decodable {
            let token: String?
        }
        return (try? JSONDecoder().decode(Session.self, from: data))?.token
    }

    // `{"code":0,"data":{"total":N,"skills":[{"skill_name":…,
    // "main_version_number":…}]}}`; code 0 with entries missing the
    // version field simply contributes nothing to the map.
    struct ListPageSummary {
        let total: Int
        let returned: Int
        let versions: [String: String]
    }

    static func parseListPage(from data: Data) throws -> ListPageSummary {
        struct Entry: Decodable {
            let skillName: String?
            let mainVersionNumber: String?

            enum CodingKeys: String, CodingKey {
                case skillName = "skill_name"
                case mainVersionNumber = "main_version_number"
            }
        }
        struct Page: Decodable {
            let total: Int?
            let skills: [Entry]?
        }
        struct Response: Decodable {
            let code: Int?
            let data: Page?
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ClientError.malformedResponse
        }
        guard response.code == 0 else {
            throw ClientError.apiRejected
        }
        var versions: [String: String] = [:]
        for entry in response.data?.skills ?? [] {
            if let name = entry.skillName,
               let version = entry.mainVersionNumber,
               !name.isEmpty,
               !version.isEmpty
            {
                versions[name] = version
            }
        }
        return ListPageSummary(
            total: response.data?.total ?? 0,
            returned: response.data?.skills?.count ?? 0,
            versions: versions
        )
    }

    // `{"code":0,"data":{"main_version_number":"v10"}}`; code 0 with a data
    // payload lacking the field (or data itself missing) means the skill has
    // no readable version — nil, not an error. Any other code rejects the
    // response so transport problems surface as failures.
    static func parseDetailResponse(from data: Data) throws -> String? {
        struct Detail: Decodable {
            let mainVersionNumber: String?

            enum CodingKeys: String, CodingKey {
                case mainVersionNumber = "main_version_number"
            }
        }
        struct Response: Decodable {
            let code: Int?
            let data: Detail?
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ClientError.malformedResponse
        }
        guard response.code == 0 else {
            throw ClientError.apiRejected
        }
        return response.data?.mainVersionNumber
    }
}

// Compares installed skill versions against the platform's main versions.
// Installed prefers `skynet skill list --json` (same view as Environment
// Doctor); falls back to the team lock file when the CLI probe is unavailable.
// Upgrade itself stays with the CLI.
public actor SkillUpdateChecker: SkillUpdateChecking {
    private let lockURL: URL
    private let client: any SkynetSkillVersionFetching
    private let locator: (any CLIPathLocating)?
    private let runner: (any CommandRunning)?
    private let maxConcurrent: Int

    public init(
        lockURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/skynet-skills-lock.json"),
        client: any SkynetSkillVersionFetching,
        locator: (any CLIPathLocating)? = nil,
        runner: (any CommandRunning)? = nil,
        maxConcurrent: Int = 6
    ) {
        self.lockURL = lockURL
        self.client = client
        self.locator = locator
        self.runner = runner
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func checkForUpdates() async -> SkillUpdateCheckResult {
        guard await client.sessionToken() != nil else {
            return .needsLogin
        }
        guard let baseline = await loadInstalledVersions() else {
            return .failed(reason: "无法读取已安装 Skills（CLI 或 lock）")
        }
        // Versions the comparator cannot parse carry no ordering, so they
        // cannot be judged outdated either way — skip instead of guessing.
        let tracked = baseline
            .filter { _, version in SemanticVersion(version) != nil }
            .sorted { $0.key < $1.key }
        guard !tracked.isEmpty else {
            return .failed(reason: "没有可识别版本的已安装 Skill")
        }

        // The list endpoint answers for ~every skill in a couple of pages;
        // per-name detail is only the fallback for names it did not cover
        // (or the whole batch failing).
        var latestVersions = (try? await client.latestMainVersions()) ?? [:]
        let unresolved = tracked
            .map(\.key)
            .filter { latestVersions[$0] == nil }
        for chunk in unresolved.chunked(into: maxConcurrent) {
            await withTaskGroup(of: (String, String?).self) { group in
                for name in chunk {
                    group.addTask {
                        (name, try? await self.client.latestMainVersion(for: name))
                    }
                }
                for await (name, latest) in group {
                    latestVersions[name] = latest
                }
            }
        }

        // Nothing resolved at all means the platform was unreachable (or
        // the login went stale between checks) — reporting "all current"
        // on zero data would be a false clean bill.
        let resolvedCount = tracked
            .filter { latestVersions[$0.key] != nil }
            .count
        guard resolvedCount > 0 else {
            return .failed(reason: "无法从 Skynet 平台获取版本（网络或登录态问题）")
        }

        let updates = tracked.compactMap { name, installed -> SkillUpdate? in
            guard let latest = latestVersions[name],
                  let installedVersion = SemanticVersion(installed),
                  let latestVersion = SemanticVersion(latest),
                  latestVersion > installedVersion
            else {
                return nil
            }
            return SkillUpdate(
                name: name,
                installedVersion: installed,
                latestVersion: latest
            )
        }
        return .completed(
            SkillUpdateReport(totalChecked: tracked.count, updates: updates)
        )
    }

    private func loadInstalledVersions() async -> [String: String]? {
        if let fromCLI = await loadFromSkillList() {
            return fromCLI
        }
        return loadLockBaseline()
    }

    private func loadFromSkillList() async -> [String: String]? {
        guard let locator, let runner,
              let cliURL = try? await locator.locate()
        else {
            return nil
        }
        let result = await runner.run(
            executableURL: cliURL,
            arguments: ["skill", "list", "--json"],
            environment: CLIExecutionEnvironment.base(for: cliURL),
            timeout: .seconds(8)
        )
        guard !result.timedOut, result.exitCode == 0,
              let skills = SkillInventoryParser.parseInstalledSkills(
                fromJSON: Data(result.stdout.utf8)
              )
        else {
            return nil
        }
        var versions: [String: String] = [:]
        for skill in skills where !skill.version.isEmpty {
            versions[skill.name] = skill.version
        }
        return versions.isEmpty ? nil : versions
    }

    private func loadLockBaseline() -> [String: String]? {
        guard let data = try? Data(contentsOf: lockURL) else {
            return nil
        }
        return SkillInventoryParser.parseLockBaseline(fromJSON: data)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else {
            return []
        }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
