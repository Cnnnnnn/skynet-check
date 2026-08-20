import Foundation

public struct CheckDurationStats: Equatable, Sendable {
    public private(set) var recent: [TimeInterval] = []

    public static let maxEntries = 10

    public init() {}

    public mutating func record(_ duration: TimeInterval) {
        recent.append(duration)
        if recent.count > Self.maxEntries {
            recent.removeFirst(recent.count - Self.maxEntries)
        }
    }

    public var last: TimeInterval? {
        recent.last
    }

    public var average: TimeInterval? {
        guard !recent.isEmpty else {
            return nil
        }
        return recent.reduce(0, +) / Double(recent.count)
    }
}

public struct SkynetConfigSummary: Equatable, Sendable {
    public let mode: String?
    public let role: String?
    public let language: String?

    public init(mode: String?, role: String?, language: String?) {
        self.mode = mode
        self.role = role
        self.language = language
    }
}

// Reads the non-sensitive settings the Skynet CLI keeps in config.json
// (mode / role / language). Session and token material is never touched.
public struct SkynetConfigReader: Sendable {
    private let configURL: URL

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skynet-cli/config.json")
    ) {
        self.configURL = configURL
    }

    public func read() -> SkynetConfigSummary? {
        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }
        struct Fields: Decodable {
            let mode: String?
            let role: String?
            let language: String?
        }
        guard let fields = try? JSONDecoder().decode(Fields.self, from: data) else {
            return nil
        }
        return SkynetConfigSummary(
            mode: fields.mode,
            role: fields.role,
            language: fields.language
        )
    }
}

public extension DurationPresentation {
    static func summarizeSeconds(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "\(Int(interval * 1000))ms"
        }
        return String(format: "%.1fs", interval)
    }
}
