import Foundation
import XCTest
@testable import SkynetMonitorCore

final class McpVersionCheckerTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    private func writeTemporaryFile(json: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        // swiftlint:disable:next force_try
        try! json.write(to: url, atomically: true, encoding: .utf8)
        temporaryURLs.append(url)
        return url
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }

    // MARK: - McpVersionChecker integration

    func testMcpCheckerProducesFindings() async throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet-base")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet-base","version":"2.11.5",
         "bin":{"skynet-mcp":"dist/mcp.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        // The configured path must exist on disk, or the checker treats it
        // as unresolvable and skips the node_modules lookup.
        let binURL = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: binURL,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: binURL.appendingPathComponent("skynet-mcp").path,
            contents: nil
        )

        let configURL = writeTemporaryFile(
            json: """
            {"mcpServers":{
              "skynet-base":{"command":"\(root.path)/bin/skynet-mcp","args":[]},
              "banking":{"command":"npx","args":["-y","@shopee/banking-fe-mcp@0.2.27"]},
              "gitlab":{"command":"npx","args":["-y","@zereight/mcp-gitlab"]}
            }}
            """
        )
        let registry = StubRegistry(
            versions: [
                "@shopee/skynet-base": "2.12.2",
                "@shopee/banking-fe-mcp": "0.2.29",
            ]
        )
        let checker = McpVersionChecker(
            cursorConfigURL: configURL,
            codexConfigURL: nil,
            registry: registry,
            binarySearchPaths: []
        )

        let findings = await checker.checkVersions()

        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(
            findings.first { $0.serverName == "skynet-base" },
            McpVersionFinding(
                serverName: "skynet-base",
                packageName: "@shopee/skynet-base",
                installedVersion: "2.11.5",
                latestVersion: "2.12.2",
                configuredCommand: "\(root.path)/bin/skynet-mcp"
            )
        )
        XCTAssertEqual(
            findings.first { $0.serverName == "banking" }?.isUpgradable,
            true
        )
        XCTAssertEqual(
            findings.first { $0.serverName == "gitlab" }?.unpinned,
            true
        )
    }

    func testMcpCheckerFallsBackToSearchPathsForMissingBinary() async throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet.bank-fe-flow")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet.bank-fe-flow","version":"0.8.9",
         "bin":{"banking-fe-mcp":"dist/cli.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let alternateBin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: alternateBin,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: alternateBin.appendingPathComponent("banking-fe-mcp").path,
            contents: nil
        )

        let configURL = writeTemporaryFile(
            json: """
            {"mcpServers":{
              "flow":{"command":"banking-fe-mcp","args":[]}
            }}
            """
        )
        let checker = McpVersionChecker(
            cursorConfigURL: configURL,
            codexConfigURL: nil,
            registry: StubRegistry(versions: ["@shopee/skynet.bank-fe-flow": "0.8.9"]),
            binarySearchPaths: [alternateBin.path]
        )

        let findings = await checker.checkVersions()

        XCTAssertEqual(
            findings,
            [
                McpVersionFinding(
                    serverName: "flow",
                    packageName: "@shopee/skynet.bank-fe-flow",
                    installedVersion: "0.8.9",
                    latestVersion: "0.8.9",
                    configuredCommand: "banking-fe-mcp"
                ),
            ]
        )
    }

    // MARK: - registry endpoints

    func testResolveEndpointsPutsNpmrcRegistryFirst() {
        let contents = """
        registry=https://nexus.npt.seabank.io/repository/npm-bank/
        //nexus.npt.seabank.io/repository/npm-bank/:_authToken=token-a
        """

        let endpoints = HTTPNpmRegistryClient.resolveEndpoints(
            fromNpmrcContents: contents
        )

        XCTAssertEqual(endpoints.count, 2)
        XCTAssertEqual(
            endpoints.first?.url.absoluteString,
            "https://nexus.npt.seabank.io/repository/npm-bank"
        )
        XCTAssertEqual(endpoints.first?.authHost, "nexus.npt.seabank.io")
    }

    func testResolveEndpointsDedupesAndFallsBack() {
        // A registry matching a built-in collapses instead of duplicating.
        let duplicate = HTTPNpmRegistryClient.resolveEndpoints(
            fromNpmrcContents: "registry=https://npm.shopee.io/"
        )
        XCTAssertEqual(duplicate.count, 2)
        XCTAssertEqual(duplicate.first?.authHost, "npm.shopee.io")

        let none = HTTPNpmRegistryClient.resolveEndpoints(fromNpmrcContents: nil)
        XCTAssertEqual(
            none.map(\.authHost),
            ["npm.shopee.io", "nexus.npt.seabank.io"]
        )
    }

    func testCursorAndCodexConfigFindingsCarrySource() async throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet-base")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet-base","version":"2.6.0",
         "bin":{"skynet-mcp":"dist/mcp.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let binURL = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: binURL,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: binURL.appendingPathComponent("skynet-mcp").path,
            contents: nil
        )

        let cursorConfig = writeTemporaryFile(
            json: """
            {"mcpServers":{
              "skynet-base":{"command":"\(root.path)/bin/skynet-mcp","args":[]}
            }}
            """
        )
        let codexConfig = writeTemporaryFile(
            json: """
            [mcp_servers.skynet-base]
            command = "\(root.path)/bin/skynet-mcp"
            args = []
            """
        )
        let checker = McpVersionChecker(
            cursorConfigURL: cursorConfig,
            codexConfigURL: codexConfig,
            registry: StubRegistry(versions: ["@shopee/skynet-base": "2.12.2"]),
            binarySearchPaths: []
        )

        let findings = await checker.checkVersions()

        XCTAssertEqual(
            findings.map { "\($0.serverName)|\($0.configSource)" },
            [
                "skynet-base|Codex",
                "skynet-base|Cursor",
            ]
        )
        XCTAssertTrue(findings.allSatisfy(\.isUpgradable))
    }}
