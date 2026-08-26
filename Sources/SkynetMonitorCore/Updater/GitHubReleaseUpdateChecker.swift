import Foundation

// Update source backed by this project's GitHub releases: the release
// workflow attaches a DMG to each v* tag, so "latest release" is the
// update manifest. The tag (v0.9.0) maps to the version, and the first
// .dmg asset becomes the download link.
public actor GitHubReleaseUpdateChecker: AppUpdateChecking {
    struct Payload: Decodable {
        let tagName: String
        let body: String?
        let assets: [Asset]
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case assets
            case draft
            case prerelease
        }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private let apiURL: URL
    private let session: URLSession

    public init(
        apiURL: URL = URL(
            string: "https://api.github.com/repos/Cnnnnnn/skynet-check/releases/latest"
        )!,
        session: URLSession = .shared
    ) {
        self.apiURL = apiURL
        self.session = session
    }

    public func latestRelease() async throws -> AppUpdateManifest {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            // A 404 here means no release exists yet — same user-visible
            // outcome as any other failure: the panel reports 检查失败.
            throw UpdateCheckError.http(status: status)
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.draft,
              !payload.prerelease,
              let dmg = payload.assets.first(where: { $0.name.hasSuffix(".dmg") })
        else {
            throw UpdateCheckError.noDMGAsset
        }
        // The tag carries the "v"; SemanticVersion strips it again during
        // evaluation, but keep the bare number for display parity with
        // the manifest format.
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        return AppUpdateManifest(
            version: version,
            downloadURL: dmg.browserDownloadURL,
            notes: payload.body
        )
    }
}

public enum UpdateCheckError: Error, LocalizedError {
    case http(status: Int)
    case noDMGAsset

    public var errorDescription: String? {
        switch self {
        case .http(let status):
            "GitHub API returned HTTP \(status)"
        case .noDMGAsset:
            "Latest release has no .dmg asset"
        }
    }
}
