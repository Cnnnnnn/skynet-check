import Foundation

public struct LoginStateSnapshot: Codable, Equatable, Sendable {
    public let state: LoginState
    public let completedAt: Date

    public init(state: LoginState, completedAt: Date) {
        self.state = state
        self.completedAt = completedAt
    }
}

public protocol LoginStateStoring: AnyObject, Sendable {
    func load() -> LoginStateSnapshot?
    func save(_ snapshot: LoginStateSnapshot)
}

public final class LoginStateStore: LoginStateStoring, @unchecked Sendable {
    private static let storageKey = "lastLoginStateSnapshot"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LoginStateSnapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try? Self.decoder.decode(LoginStateSnapshot.self, from: data)
    }

    public func save(_ snapshot: LoginStateSnapshot) {
        guard let data = try? Self.encoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
