import Foundation

// Reads service tokens (e.g. the Confluence token) that the Skynet CLI
// stores in ~/.skynet-cli/tokens.json so the panel can offer copy actions.
//
// Token values are sensitive: they are masked in the UI, never logged,
// never included in diagnostics, and never persisted by this app — the
// file remains the single source of truth.
public struct ServiceToken: Equatable, Sendable {
    public let key: String
    public let displayName: String
    public let value: String

    public init(key: String, displayName: String, value: String) {
        self.key = key
        self.displayName = displayName
        self.value = value
    }

    // Short masked form for on-screen display, e.g. "sk-1a…9f2a".
    public var maskedValue: String {
        guard value.count > 8 else {
            return String(repeating: "•", count: max(value.count, 4))
        }
        return "\(value.prefix(4))…\(value.suffix(4))"
    }
}

public protocol ServiceTokenReading: Sendable {
    func availableTokens() -> [ServiceToken]
}

public struct ServiceTokenStore: ServiceTokenReading {
    private static let displayNames: [String: String] = [
        "CONFLUENCE_TOKEN": "Confluence",
    ]

    private let tokensURL: URL

    public init(
        tokensURL: URL = SkynetEndpoints.homeRelative(SkynetEndpoints.tokensPath)
    ) {
        self.tokensURL = tokensURL
    }

    public func availableTokens() -> [ServiceToken] {
        guard let data = try? Data(contentsOf: tokensURL),
              let entries = try? JSONDecoder().decode(
                  [String: String].self,
                  from: data
              )
        else {
            return []
        }

        return entries
            .filter { !$0.value.isEmpty }
            .map { key, value in
                ServiceToken(
                    key: key,
                    displayName: Self.displayNames[key] ?? key,
                    value: value
                )
            }
            .sorted { $0.key < $1.key }
    }
}
