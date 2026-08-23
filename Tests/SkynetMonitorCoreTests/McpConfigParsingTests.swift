import Foundation
import XCTest
@testable import SkynetMonitorCore

final class McpConfigParsingTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }

    // MARK: - MCP plan and config parsing

    func testNpxPlanResolvesPinnedScopedPackage() {
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "/Users/x/.nvm/versions/node/v18.17.0/bin/npx",
                arguments: ["-y", "@shopee/banking-fe-mcp@0.2.27"]
            ),
            .npxPinned(package: "@shopee/banking-fe-mcp", pinnedVersion: "0.2.27")
        )
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "npx",
                arguments: ["-y", "-p", "@scope/tool", "--flag"]
            ),
            .npxUnpinned(package: "@scope/tool")
        )
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "npx",
                arguments: ["-y", "@zereight/mcp-gitlab"]
            ),
            .npxUnpinned(package: "@zereight/mcp-gitlab")
        )
    }

    func testBinaryPlansResolve() {
        XCTAssertEqual(
            McpServerPlan.plan(
                command: "/Users/x/.nvm/versions/node/v18.17.0/bin/skynet-mcp",
                arguments: ["--mcp=skynet-base"]
            ),
            .globalBinary(
                binaryName: "skynet-mcp",
                binaryDirectory: "/Users/x/.nvm/versions/node/v18.17.0/bin"
            )
        )
        // Bare command names cannot be resolved without a PATH search.
        XCTAssertNil(
            McpServerPlan.plan(command: "banking-fe-mcp", arguments: [])
        )
        XCTAssertNil(
            McpServerPlan.plan(command: "npx", arguments: ["-y"])
        )
    }

    func testMcpConfigParsing() {
        let data = Data(
            """
            {"mcp":{"servers":{
              "zeta":{"type":"stdio","command":"npx","args":["-y","p@1.0"]},
              "alpha":{"type":"stdio","command":"/bin/alpha","args":[]},
              "broken":{"type":"stdio","args":[]}
            }}}
            """
                .utf8
        )

        let entries = McpConfigParser.parseServers(from: data)

        XCTAssertEqual(
            entries,
            [
                McpServerEntry(name: "alpha", command: "/bin/alpha", arguments: []),
                McpServerEntry(name: "zeta", command: "npx", arguments: ["-y", "p@1.0"]),
            ]
        )
        XCTAssertNil(McpConfigParser.parseServers(from: Data("nope".utf8)))
    }

    // MARK: - node_modules resolution

    func testNodeModulesReaderFindsOwningPackage() throws {
        let root = makeTemporaryDirectory()
        let packageURL = root
            .appendingPathComponent("lib/node_modules/@shopee/skynet-base")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try """
        {"name":"@shopee/skynet-base","version":"2.11.5",
         "bin":{"skynet-base":"dist/cli.js","skynet-mcp":"dist/mcp.js"}}
        """
        .write(to: packageURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let package = NodeModulesPackageReader.package(
            owningBinary: "skynet-mcp",
            inBinaryDirectory: root.appendingPathComponent("bin").path
        )

        XCTAssertEqual(package?.name, "@shopee/skynet-base")
        XCTAssertEqual(package?.version, "2.11.5")
        XCTAssertNil(
            NodeModulesPackageReader.package(
                owningBinary: "unknown-binary",
                inBinaryDirectory: root.appendingPathComponent("bin").path
            )
        )
    }

    // MARK: - registry parsing

    func testRegistryResponseParsing() {
        XCTAssertEqual(
            HTTPNpmRegistryClient.parseLatestDocument(
                from: Data(#"{"name":"@shopee/skynet-cli","version":"2.8.0"}"#.utf8)
            ),
            "2.8.0"
        )
        XCTAssertEqual(
            HTTPNpmRegistryClient.parsePackumentDistTag(
                from: Data(#"{"name":"x","dist-tags":{"latest":"0.2.29","beta":"0.3.0"}}"#.utf8)
            ),
            "0.2.29"
        )
        XCTAssertNil(
            HTTPNpmRegistryClient.parseLatestDocument(from: Data("{}".utf8))
        )
    }

    func testNpmrcTokenParsing() {
        let contents = """
        registry=https://nexus.npt.seabank.io/repository/npm-bank/
        //nexus.npt.seabank.io/repository/npm-bank/:_authToken=token-a
        //npm.shopee.io/:_authToken="token-b"
        unrelated=line
        """

        let tokens = HTTPNpmRegistryClient.parseRegistryTokens(fromNpmrc: contents)

        XCTAssertEqual(
            tokens["nexus.npt.seabank.io"],
            "token-a"
        )
        XCTAssertEqual(tokens["npm.shopee.io"], "token-b")
        XCTAssertEqual(tokens.count, 2)
    }
}
