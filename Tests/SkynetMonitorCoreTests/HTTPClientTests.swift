import Foundation
import XCTest
@testable import SkynetMonitorCore

// Exercises the HTTP clients' request construction through a stubbed
// URLProtocol: Cookie header, pagination, endpoint order, and fallback —
// everything the pure parse-function tests cannot see.
final class HTTPClientTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        StubURLProtocol.handler = nil
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    // MARK: - Skynet platform client

    func testDetailSendsSessionCookieAndExpectedURL() async throws {
        let sessionURL = writeTemporaryFile(json: #"{"token":"abc123"}"#)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://platform.test/api/platform/agent_skill/v1/detail?skill_name=fe-api-gen"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Cookie"),
                "SPC_CS_SKYNET=abc123"
            )
            let body = #"{"code":0,"data":{"main_version_number":"v10"}}"#
            return (200, Data(body.utf8))
        }
        let client = HTTPSkynetPlatformClient(
            sessionURL: sessionURL,
            apiBase: URL(string: "https://platform.test")!,
            session: stubSession()
        )

        let version = try await client.latestMainVersion(for: "fe-api-gen")

        XCTAssertEqual(version, "v10")
    }

    func testOmitsCookieWhenSessionFileMissing() async throws {
        let missingSession = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (200, Data(#"{"code":0,"data":null}"#.utf8))
        }
        let client = HTTPSkynetPlatformClient(
            sessionURL: missingSession,
            apiBase: URL(string: "https://platform.test")!,
            session: stubSession()
        )

        let version = try await client.latestMainVersion(for: "any")

        XCTAssertNil(version)
    }

    func testListPaginatesUntilTotalCovered() async throws {
        let requestedPages = PageLog()
        StubURLProtocol.handler = { request in
            let components = URLComponents(
                url: request.url!,
                resolvingAgainstBaseURL: false
            )
            let page = components?.queryItems?
                .first { $0.name == "page" }?.value
                .flatMap(Int.init) ?? 0
            requestedPages.append(page)
            if page == 1 {
                return (200, Self.listBody(count: 500, total: 700, offset: 0))
            }
            return (200, Self.listBody(count: 200, total: 700, offset: 500))
        }
        let client = HTTPSkynetPlatformClient(
            sessionURL: writeTemporaryFile(json: #"{"token":"t"}"#),
            apiBase: URL(string: "https://platform.test")!,
            session: stubSession()
        )

        let versions = try await client.latestMainVersions()

        XCTAssertEqual(versions.count, 700)
        XCTAssertEqual(versions["skill-499"], "v1")
        XCTAssertEqual(requestedPages.pages, [1, 2])
    }

    func testListStopsOnShortPage() async throws {
        let requestedPages = PageLog()
        StubURLProtocol.handler = { request in
            let components = URLComponents(
                url: request.url!,
                resolvingAgainstBaseURL: false
            )
            let page = components?.queryItems?
                .first { $0.name == "page" }?.value
                .flatMap(Int.init) ?? 0
            requestedPages.append(page)
            return (200, Self.listBody(count: 3, total: 3, offset: 0))
        }
        let client = HTTPSkynetPlatformClient(
            sessionURL: writeTemporaryFile(json: #"{"token":"t"}"#),
            apiBase: URL(string: "https://platform.test")!,
            session: stubSession()
        )

        let versions = try await client.latestMainVersions()

        XCTAssertEqual(versions.count, 3)
        XCTAssertEqual(requestedPages.pages, [1])
    }

    // MARK: - npm registry client

    func testRegistryPrefersNpmrcRegistryAndAttachesToken() async throws {
        let npmrcURL = writeTemporaryFile(
            json: """
            registry=https://reg.example/repository/npm
            //reg.example/repository/npm/:_authToken=tok-1
            """
        )
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "reg.example")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://reg.example/repository/npm/@shopee%2Fskynet-base"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer tok-1"
            )
            return (200, Data(#"{"dist-tags":{"latest":"2.12.2"}}"#.utf8))
        }
        let client = HTTPNpmRegistryClient(
            npmrcURL: npmrcURL,
            session: stubSession()
        )

        let version = await client.latestVersion(of: "@shopee/skynet-base")

        XCTAssertEqual(version, "2.12.2")
    }

    func testRegistryFallsBackToNextEndpoint() async throws {
        let hosts = PageLog()
        StubURLProtocol.handler = { request in
            let host = request.url?.host ?? ""
            hosts.append(0)
            if host == "first.test" {
                return (404, Data())
            }
            return (200, Data(#"{"name":"x","version":"0.2.29"}"#.utf8))
        }
        let client = HTTPNpmRegistryClient(
            endpoints: [
                HTTPNpmRegistryClient.Endpoint(
                    url: URL(string: "https://first.test")!,
                    authHost: "first.test"
                ),
                HTTPNpmRegistryClient.Endpoint(
                    url: URL(string: "https://second.test")!,
                    authHost: "second.test"
                ),
            ],
            npmrcURL: nil,
            session: stubSession()
        )

        let version = await client.latestVersion(of: "@shopee/banking-fe-mcp")

        XCTAssertEqual(version, "0.2.29")
        XCTAssertEqual(hosts.pages.count, 2)
    }

    // MARK: - helpers

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func writeTemporaryFile(json: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        // swiftlint:disable:next force_try
        try! json.write(to: url, atomically: true, encoding: .utf8)
        temporaryURLs.append(url)
        return url
    }

    private static func listBody(
        count: Int,
        total: Int,
        offset: Int
    ) -> Data {
        let entries = (0..<count)
            .map {
                "{\"skill_name\":\"skill-\($0 + offset)\",\"main_version_number\":\"v1\"}"
            }
            .joined(separator: ",")
        return Data("{\"code\":0,\"data\":{\"total\":\(total),\"skills\":[\(entries)]}}".utf8)
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> (Int, Data))?

    static var handler: (@Sendable (URLRequest) -> (Int, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _handler = newValue
        }
    }

    // URLProtocol requires class methods for overriding; `static` cannot
    // participate in overrides, so the lint suggestion does not apply here.

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unsupportedURL)
            )
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// Tiny thread-safe recorder; doubles as a page/counter log.
private final class PageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _pages: [Int] = []

    var pages: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _pages
    }

    func append(_ page: Int) {
        lock.lock()
        defer { lock.unlock() }
        _pages.append(page)
    }
}
