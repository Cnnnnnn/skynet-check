import Foundation

public enum ServiceTokenValidationOutcome: Equatable, Sendable {
    case valid
    case invalid
    case unknown

    var logLabel: String {
        switch self {
        case .valid:
            "valid"
        case .invalid:
            "invalid"
        case .unknown:
            "unknown"
        }
    }

    public var panelDetail: String {
        switch self {
        case .valid:
            MonitorText.ServiceToken.validDetail
        case .invalid:
            MonitorText.ServiceToken.invalidDetail
        case .unknown:
            MonitorText.ServiceToken.unknownDetail
        }
    }
}

public protocol ServiceTokenValidating: Sendable {
    var supportedKeys: Set<String> { get }
    func validate(token: ServiceToken) async -> ServiceTokenValidationOutcome
}

// Probes the Confluence REST API with the stored token. The endpoint
// answers 200 with "type":"known" for an accepted token and "type":
// "anonymous" otherwise, so the response body decides the outcome.
// Token values travel only in the Authorization header and never reach
// logs or diagnostics.
public struct ConfluenceTokenValidator: ServiceTokenValidating {
    public let supportedKeys: Set<String> = ["CONFLUENCE_TOKEN"]

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://confluence.shopee.io")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func validate(token: ServiceToken) async -> ServiceTokenValidationOutcome {
        guard supportedKeys.contains(token.key) else {
            return .unknown
        }

        var request = URLRequest(
            url: baseURL.appendingPathComponent("rest/api/user/current")
        )
        request.timeoutInterval = 8
        request.setValue(
            "Bearer \(token.value)",
            forHTTPHeaderField: "Authorization"
        )

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return Self.outcome(statusCode: statusCode, body: data)
        } catch {
            return .unknown
        }
    }

    static func outcome(statusCode: Int?, body: Data) -> ServiceTokenValidationOutcome {
        guard let statusCode else {
            return .unknown
        }
        if statusCode == 401 || statusCode == 403 {
            return .invalid
        }
        guard statusCode == 200 else {
            return .unknown
        }

        struct User: Decodable {
            let type: String
        }

        guard let user = try? JSONDecoder().decode(User.self, from: body) else {
            return .unknown
        }
        switch user.type {
        case "known":
            return .valid
        case "anonymous":
            return .invalid
        default:
            return .unknown
        }
    }
}
