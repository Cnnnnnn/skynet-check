import Foundation

// The last component-version check persisted across launches: the panel
// shows it immediately on startup while a fresh check runs in the
// background, instead of a blank card until the network answers.
public struct ComponentUpdateSnapshot: Codable, Equatable, Sendable {
    public let savedAt: Date
    public let skillPhase: ComponentUpdatePhase
    public let skillReport: SkillUpdateReport?
    public let mcpFindings: [McpVersionFinding]

    public init(
        savedAt: Date,
        skillPhase: ComponentUpdatePhase,
        skillReport: SkillUpdateReport?,
        mcpFindings: [McpVersionFinding]
    ) {
        self.savedAt = savedAt
        self.skillPhase = skillPhase
        self.skillReport = skillReport
        self.mcpFindings = mcpFindings
    }
}

public protocol ComponentUpdateSnapshotStoring: AnyObject, Sendable {
    func load() -> ComponentUpdateSnapshot?
    func save(_ snapshot: ComponentUpdateSnapshot)
}

public final class ComponentUpdateSnapshotStore: ComponentUpdateSnapshotStoring, @unchecked Sendable {
    private static let storageKey = "componentUpdateSnapshot"
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

    public func load() -> ComponentUpdateSnapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try? Self.decoder.decode(ComponentUpdateSnapshot.self, from: data)
    }

    public func save(_ snapshot: ComponentUpdateSnapshot) {
        guard let data = try? Self.encoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
