import Foundation
import XCTest
@testable import SkynetMonitorCore

final class SkillUpdateCheckerTests: XCTestCase {
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

    // MARK: - Platform client parsing

    func testDetailResponseParsesMainVersion() throws {
        let body = #"{"code":0,"msg":"success","data":{"skill_name":"fe-api-gen","main_version_number":"v10"}}"#

        XCTAssertEqual(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data(body.utf8)),
            "v10"
        )
    }

    func testDetailResponseWithoutDataIsNotAnError() throws {
        let body = #"{"code":0,"msg":"success","data":null}"#

        XCTAssertNil(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data(body.utf8))
        )
    }

    func testDetailResponseRejectsNonZeroCode() {
        let body = #"{"code":401,"msg":"unauthorized"}"#

        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data(body.utf8))
        ) { error in
            XCTAssertEqual(
                error as? HTTPSkynetPlatformClient.ClientError,
                .apiRejected
            )
        }
        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseDetailResponse(from: Data("not json".utf8))
        ) { error in
            XCTAssertEqual(
                error as? HTTPSkynetPlatformClient.ClientError,
                .malformedResponse
            )
        }
    }

    func testSessionTokenParsing() {
        XCTAssertEqual(
            HTTPSkynetPlatformClient.parseSessionToken(
                from: Data(#"{"sessionId":"s","token":"abc"}"#.utf8)
            ),
            "abc"
        )
        XCTAssertNil(
            HTTPSkynetPlatformClient.parseSessionToken(
                from: Data(#"{"sessionId":"s"}"#.utf8)
            )
        )
    }

    func testListPageParsesVersionsAndTotals() throws {
        let body = """
        {"code":0,"data":{"total":1165,"page":1,"skills":[
          {"skill_name":"fe-api-gen","main_version_number":"v11"},
          {"skill_name":"no-version-skill"},
          {"skill_name":"bank-react-sdd-base-skill-v2","main_version_number":"v170"}
        ]}}
        """

        let result = try HTTPSkynetPlatformClient.parseListPage(
            from: Data(body.utf8)
        )

        XCTAssertEqual(result.total, 1165)
        XCTAssertEqual(result.returned, 3)
        XCTAssertEqual(
            result.versions,
            [
                "fe-api-gen": "v11",
                "bank-react-sdd-base-skill-v2": "v170",
            ]
        )
        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseListPage(from: Data("nope".utf8))
        )
        XCTAssertThrowsError(
            try HTTPSkynetPlatformClient.parseListPage(
                from: Data(#"{"code":401,"data":null}"#.utf8)
            )
        )
    }

    func testSkillCheckerPrefersBatchOverDetail() async throws {
        let lockURL = writeTemporaryFile(
            json: """
            {"fe-api-gen": {"version": "v10"}, "gone-skill": {"version": "v1"}}
            """
        )
        let client = StubPlatformClient(
            token: "session-token",
            latest: ["fe-api-gen": "v10", "gone-skill": "v2"],
            batch: ["fe-api-gen": "v11"]
        )
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(
                SkillUpdateReport(
                    totalChecked: 2,
                    updates: [
                        // Batch's v11 wins over detail's v10; the name the
                        // batch missed falls back to detail.
                        SkillUpdate(name: "fe-api-gen", installedVersion: "v10", latestVersion: "v11"),
                        SkillUpdate(name: "gone-skill", installedVersion: "v1", latestVersion: "v2"),
                    ]
                )
            )
        )
    }

    func testSkillCheckerFallsBackToDetailWhenBatchFails() async throws {
        let lockURL = writeTemporaryFile(
            json: #"{"fe-api-gen": {"version": "v10"}}"#
        )
        let client = StubPlatformClient(token: "session-token", latest: ["fe-api-gen": "v11"], batch: [:])
        client.batchFails = true
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(
                SkillUpdateReport(
                    totalChecked: 1,
                    updates: [
                        SkillUpdate(name: "fe-api-gen", installedVersion: "v10", latestVersion: "v11"),
                    ]
                )
            )
        )
    }

    // MARK: - SkillUpdateChecker

    func testSkillCheckerReportsOutdatedSkills() async throws {
        let lockURL = writeTemporaryFile(
            json: """
            {
              "fe-api-gen": {"version": "v10"},
              "bank-react-sdd-base-skill-v2": {"version": "v145"},
              "broken-version": {"version": "dev"}
            }
            """
        )
        let client = StubPlatformClient(
            token: "session-token",
            latest: [
                "fe-api-gen": "v10",
                "bank-react-sdd-base-skill-v2": "v170",
                "broken-version": "v999",
            ]
        )
        let checker = SkillUpdateChecker(
            lockURL: lockURL,
            client: client,
            maxConcurrent: 2
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(
                SkillUpdateReport(
                    totalChecked: 2,
                    updates: [
                        SkillUpdate(
                            name: "bank-react-sdd-base-skill-v2",
                            installedVersion: "v145",
                            latestVersion: "v170"
                        ),
                    ]
                )
            )
        )
    }

    func testSkillCheckerRequiresLoginWithoutSessionToken() async {
        let lockURL = writeTemporaryFile(json: #"{"a":{"version":"v1"}}"#)
        let checker = SkillUpdateChecker(
            lockURL: lockURL,
            client: StubPlatformClient(token: nil, latest: [:])
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .needsLogin)
    }

    func testSkillCheckerFailsWithoutLockFile() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let checker = SkillUpdateChecker(
            lockURL: missingURL,
            client: StubPlatformClient(token: "session-token", latest: [:])
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .failed(reason: "无法读取 skill lock 文件"))
    }

    func testSkillCheckerTreatsFetchErrorsAsUnknown() async throws {
        let lockURL = writeTemporaryFile(
            json: #"{"fe-api-gen": {"version": "v10"}, "gone-skill": {"version": "v1"}}"#
        )
        let client = StubPlatformClient(token: "session-token", latest: ["fe-api-gen": "v10"])
        // One name resolves, one fails: the check still completes and the
        // unresolved one is simply not judged.
        client.failingSkills = ["gone-skill"]
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        XCTAssertEqual(
            result,
            .completed(SkillUpdateReport(totalChecked: 2, updates: []))
        )
    }

    func testSkillCheckerFailsWhenNothingResolved() async throws {
        let lockURL = writeTemporaryFile(
            json: #"{"fe-api-gen": {"version": "v10"}}"#
        )
        let client = StubPlatformClient(token: "session-token", latest: [:])
        client.failingSkills = ["fe-api-gen"]
        let checker = SkillUpdateChecker(lockURL: lockURL, client: client)

        let result = await checker.checkForUpdates()

        // Zero resolved names must not masquerade as "everything current".
        XCTAssertEqual(
            result,
            .failed(reason: "无法从 Skynet 平台获取版本（网络或登录态问题）")
        )
    }
}
