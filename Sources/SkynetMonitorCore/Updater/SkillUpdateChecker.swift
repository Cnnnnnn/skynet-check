import Foundation

public struct SkillUpdate: Equatable, Sendable {
    public let name: String
    public let installedVersion: String
    public let latestVersion: String

    public init(name: String, installedVersion: String, latestVersion: String) {
        self.name = name
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
    }
}

public struct SkillUpdateReport: Equatable, Sendable {
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
    case failed

    var logLabel: String {
        switch self {
        case .needsLogin:
            "needs login"
        case let .completed(report):
            "completed, \(report.updates.count) of \(report.totalChecked) upgradable"
        case .failed:
            "failed"
        }
    }
}

// Panel-facing phase for the component-version card; the detailed lists are
// carried by the separate published findings.
public enum ComponentUpdatePhase: Equatable, Sendable {
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
        sessionURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skynet-cli/session.json"),
        apiBase: URL = URL(string: "https://de.shopee.io")!,
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
    static func parseListPage(from data: Data) throws -> (
        total: Int,
        returned: Int,
        versions: [String: String]
    ) {
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
        return (
            response.data?.total ?? 0,
            response.data?.skills?.count ?? 0,
            versions
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

// Compares the local team lock baseline (the same file `skynet skill list`
// reports from) against the platform's main versions. Only detection — the
// upgrade command stays with the CLI.
public actor SkillUpdateChecker: SkillUpdateChecking {
    private let lockURL: URL
    private let client: any SkynetSkillVersionFetching
    private let maxConcurrent: Int

    public init(
        lockURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/skynet-skills-lock.json"),
        client: any SkynetSkillVersionFetching,
        maxConcurrent: Int = 6
    ) {
        self.lockURL = lockURL
        self.client = client
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func checkForUpdates() async -> SkillUpdateCheckResult {
        guard await client.sessionToken() != nil else {
            return .needsLogin
        }
        guard let baseline = loadBaseline() else {
            return .failed
        }
        // Versions the comparator cannot parse carry no ordering, so they
        // cannot be judged outdated either way — skip instead of guessing.
        let tracked = baseline
            .filter { _, version in SemanticVersion(version) != nil }
            .sorted { $0.key < $1.key }
        guard !tracked.isEmpty else {
            return .failed
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

    private func loadBaseline() -> [String: String]? {
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
