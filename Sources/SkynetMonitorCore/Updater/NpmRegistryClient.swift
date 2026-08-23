import Foundation

public protocol NpmRegistryLatestFetching: Sendable {
    func latestVersion(of package: String) async -> String?
}

// Reads the "latest" dist-tag from the registries the Skynet MCP packages
// live on. `@shopee/skynet.*` publishes to npm.shopee.io; the pinned
// banking-fe-mcp package only exists on the Nexus bank registry, so both
// are probed in order.
public actor HTTPNpmRegistryClient: NpmRegistryLatestFetching {
    public struct Endpoint: Equatable, Sendable {
        let url: URL
        let authHost: String

        public init(url: URL, authHost: String) {
            self.url = url
            self.authHost = authHost
        }
    }

    private let endpoints: [Endpoint]
    private let npmrcURL: URL?
    private let session: URLSession

    public init(
        endpoints: [Endpoint]? = nil,
        npmrcURL: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".npmrc"),
        session: URLSession = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            return configuration
        }())
    ) {
        self.endpoints = endpoints ?? Self.resolveEndpoints(
            fromNpmrcContents: npmrcURL.flatMap {
                try? String(contentsOf: $0, encoding: .utf8)
            }
        )
        self.npmrcURL = npmrcURL
        self.session = session
    }

    // The npmrc default registry goes first (the user's own mirror wins),
    // then the known Skynet registries as fallbacks; duplicates collapse.
    static func resolveEndpoints(
        fromNpmrcContents contents: String?
    ) -> [Endpoint] {
        var endpoints = [
            Endpoint(
                url: URL(string: "https://npm.shopee.io")!,
                authHost: "npm.shopee.io"
            ),
            Endpoint(
                url: URL(
                    string: "https://nexus.npt.seabank.io/repository/npm-bank"
                )!,
                authHost: "nexus.npt.seabank.io"
            ),
        ]
        guard let contents else {
            return endpoints
        }
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("registry=") else {
                continue
            }
            let raw = String(trimmed.dropFirst("registry=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: stripped),
                  url.scheme != nil,
                  let host = url.host
            else {
                break
            }
            let custom = Endpoint(url: url, authHost: host)
            // The user's own registry leads the probe order; a duplicate of
            // a built-in moves to the front rather than staying in place.
            if let existingIndex = endpoints.firstIndex(of: custom) {
                endpoints.remove(at: existingIndex)
            }
            endpoints.insert(custom, at: 0)
            break
        }
        return endpoints
    }

    public func latestVersion(of package: String) async -> String? {
        let tokens = loadRegistryTokens()
        for endpoint in endpoints {
            // Both appendingPathComponent and URLComponents.path would
            // re-encode "%2F" into "%252F"; URL(string:) with a
            // pre-escaped path leaves the sequence verbatim.
            guard let escaped = addingPercentEncoding(forPackage: package),
                  let url = URL(
                      string: endpoint.url.absoluteString + "/" + escaped
                  )
            else {
                continue
            }
            var request = URLRequest(url: url)
            if let token = tokens[endpoint.authHost] {
                request.setValue(
                    "Bearer \(token)",
                    forHTTPHeaderField: "Authorization"
                )
            }
            guard let (data, response) = try? await session.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                continue
            }
            // `/latest` serves {"name","version"}; the full packument keeps
            // the answer under dist-tags.
            if let version = Self.parseLatestDocument(from: data)
                ?? Self.parsePackumentDistTag(from: data)
            {
                return version
            }
        }
        return nil
    }

    private func loadRegistryTokens() -> [String: String] {
        guard let npmrcURL,
              let contents = try? String(contentsOf: npmrcURL, encoding: .utf8)
        else {
            return [:]
        }
        return Self.parseRegistryTokens(fromNpmrc: contents)
    }

    static func parseRegistryTokens(fromNpmrc contents: String) -> [String: String] {
        var tokens: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // //host/path/:_authToken=<token>
            guard line.hasPrefix("//"),
                  let tokenRange = line.range(of: ":_authToken=")
            else {
                continue
            }
            let host = String(line[line.index(line.startIndex, offsetBy: 2)..<tokenRange.lowerBound])
                .split(separator: "/")
                .first
                .map(String.init) ?? ""
            let token = String(line[tokenRange.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !host.isEmpty, !token.isEmpty {
                tokens[host] = token
            }
        }
        return tokens
    }

    static func parseLatestDocument(from data: Data) -> String? {
        struct Latest: Decodable {
            let version: String
        }
        return (try? JSONDecoder().decode(Latest.self, from: data))?.version
    }

    static func parsePackumentDistTag(from data: Data) -> String? {
        struct Packument: Decodable {
            let distTags: [String: String]

            enum CodingKeys: String, CodingKey {
                case distTags = "dist-tags"
            }
        }
        return (try? JSONDecoder().decode(Packument.self, from: data))?.distTags["latest"]
    }

    func addingPercentEncoding(forPackage package: String) -> String? {
        package.replacingOccurrences(of: "/", with: "%2F")
    }
}
