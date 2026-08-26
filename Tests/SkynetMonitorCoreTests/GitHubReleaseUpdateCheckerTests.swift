import XCTest
@testable import SkynetMonitorCore

final class GitHubReleaseUpdateCheckerTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeSession(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = handler
        return URLSession(configuration: configuration)
    }

    private static func releaseJSON(tag: String, dmgName: String) -> Data {
        Data("""
        {
          "tag_name": "\(tag)",
          "body": "release notes",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "README.md", "browser_download_url": "https://example.test/r.md"},
            {"name": "\(dmgName)", "browser_download_url": "https://example.test/app.dmg"}
          ]
        }
        """.utf8)
    }

    func testMapsTagAndDMGAsset() async throws {
        let checker = GitHubReleaseUpdateChecker(
            apiURL: URL(string: "https://api.test/latest")!,
            session: makeSession { _ in
                (200, Self.releaseJSON(tag: "v0.9.0", dmgName: "Skynet Login Monitor-0.9.0.dmg"))
            }
        )

        let manifest = try await checker.latestRelease()

        XCTAssertEqual(manifest.version, "0.9.0")
        XCTAssertEqual(manifest.downloadURL, URL(string: "https://example.test/app.dmg")!)
        XCTAssertEqual(manifest.notes, "release notes")
    }

    func testNon200Throws() async {
        let checker = GitHubReleaseUpdateChecker(
            apiURL: URL(string: "https://api.test/latest")!,
            session: makeSession { _ in (404, Data("{}".utf8)) }
        )

        do {
            _ = try await checker.latestRelease()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                UpdateCheckError.http(status: 404).errorDescription
            )
        }
    }

    func testPrereleaseIsIgnoredAsNoDMG() async {
        // A prerelease or draft carries no installable DMG for our
        // purposes; the checker reports it the same as a missing asset.
        let body = Data("""
        {
          "tag_name": "v1.0.0-rc1",
          "body": null,
          "draft": false,
          "prerelease": true,
          "assets": [
            {"name": "app.dmg", "browser_download_url": "https://example.test/a.dmg"}
          ]
        }
        """.utf8)
        let checker = GitHubReleaseUpdateChecker(
            apiURL: URL(string: "https://api.test/latest")!,
            session: makeSession { _ in (200, body) }
        )

        do {
            _ = try await checker.latestRelease()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                UpdateCheckError.noDMGAsset.errorDescription
            )
        }
    }
}
