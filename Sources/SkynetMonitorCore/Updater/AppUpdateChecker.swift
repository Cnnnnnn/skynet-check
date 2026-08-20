import Foundation

public struct AppUpdateManifest: Codable, Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let notes: String?

    public init(version: String, downloadURL: URL, notes: String? = nil) {
        self.version = version
        self.downloadURL = downloadURL
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case version
        case downloadURL = "downloadUrl"
        case notes
    }

    public static func decode(from data: Data) throws -> AppUpdateManifest {
        try JSONDecoder().decode(AppUpdateManifest.self, from: data)
    }
}

public enum AppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(version: String)
    case failed

    var logLabel: String {
        switch self {
        case .idle:
            "idle"
        case .checking:
            "checking"
        case .upToDate:
            "upToDate"
        case .available:
            "available"
        case .failed:
            "failed"
        }
    }
}

public protocol AppUpdateChecking: Sendable {
    func latestRelease() async throws -> AppUpdateManifest
}

public actor HTTPAppUpdateChecker: AppUpdateChecking {
    private let manifestURL: URL
    private let session: URLSession

    public init(manifestURL: URL, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.session = session
    }

    public func latestRelease() async throws -> AppUpdateManifest {
        let (data, _) = try await session.data(from: manifestURL)
        return try AppUpdateManifest.decode(from: data)
    }
}

public enum AppUpdateEvaluator {
    public static func evaluate(
        currentVersion: String,
        manifest: AppUpdateManifest
    ) -> AppUpdateStatus {
        guard let current = SemanticVersion(currentVersion),
              let latest = SemanticVersion(manifest.version)
        else {
            return .failed
        }
        if latest > current {
            return .available(version: manifest.version)
        }
        return .upToDate(currentVersion: currentVersion)
    }
}
