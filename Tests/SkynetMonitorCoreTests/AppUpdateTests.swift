import Foundation
import XCTest
@testable import SkynetMonitorCore

final class AppUpdateTests: XCTestCase {
    func testComparesVersionsNumerically() {
        XCTAssertTrue(SemanticVersion("v10.0.0")! > SemanticVersion("v9.11.0")!)
        XCTAssertTrue(SemanticVersion("0.2.1")! > SemanticVersion("0.2.0")!)
        XCTAssertTrue(SemanticVersion("1.0.0")! > SemanticVersion("1.0")!)
        XCTAssertFalse(SemanticVersion("v20.0.0")! > SemanticVersion("v20.0.0")!)
        XCTAssertNil(SemanticVersion("no-digits"))
    }

    func testPrereleaseSortsBeforeRelease() {
        // A pre-release of the same core must not look "newer" than the
        // release itself.
        XCTAssertTrue(SemanticVersion("1.2.0")! > SemanticVersion("1.2.0-beta")!)
        XCTAssertFalse(SemanticVersion("1.2.0-beta")! > SemanticVersion("1.2.0")!)
        // But a prerelease is still newer than the previous release.
        XCTAssertTrue(SemanticVersion("1.2.0-beta")! > SemanticVersion("1.1.9")!)
    }

    func testBuildMetadataIsIgnored() {
        XCTAssertEqual(
            SemanticVersion("2.0.0+build.42")!.numbers,
            [2, 0, 0]
        )
        XCTAssertFalse(
            SemanticVersion("2.0.0+build.42")! > SemanticVersion("2.0.0")!
        )
    }

    func testShortFormEqualsPaddedZeros() {
        XCTAssertFalse(SemanticVersion("1.0")! > SemanticVersion("1.0.0")!)
        XCTAssertTrue(SemanticVersion("1.0")! > SemanticVersion("0.9.9")!)
    }

    func testEvaluatorReportsAvailableForNewerManifest() {
        let status = AppUpdateEvaluator.evaluate(
            currentVersion: "0.2.0",
            manifest: makeManifest(version: "0.3.0")
        )

        XCTAssertEqual(status, .available(version: "0.3.0"))
    }

    func testEvaluatorReportsUpToDateForSameOrOlderManifest() {
        XCTAssertEqual(
            AppUpdateEvaluator.evaluate(
                currentVersion: "0.2.0",
                manifest: makeManifest(version: "0.2.0")
            ),
            .upToDate(currentVersion: "0.2.0")
        )
        XCTAssertEqual(
            AppUpdateEvaluator.evaluate(
                currentVersion: "0.2.0",
                manifest: makeManifest(version: "0.1.9")
            ),
            .upToDate(currentVersion: "0.2.0")
        )
    }

    func testEvaluatorFailsOnUnparsableVersions() {
        XCTAssertEqual(
            AppUpdateEvaluator.evaluate(
                currentVersion: "unknown",
                manifest: makeManifest(version: "0.3.0")
            ),
            .failed
        )
    }

    func testDecodesManifestJSON() throws {
        let json = """
        {"version": "0.3.0", "downloadUrl": "https://example.internal/monitor-0.3.0.dmg", "notes": "bug fixes"}
        """

        let manifest = try AppUpdateManifest.decode(
            from: Data(json.utf8)
        )

        XCTAssertEqual(manifest.version, "0.3.0")
        XCTAssertEqual(
            manifest.downloadURL,
            URL(string: "https://example.internal/monitor-0.3.0.dmg")
        )
        XCTAssertEqual(manifest.notes, "bug fixes")
    }

    private func makeManifest(version: String) -> AppUpdateManifest {
        AppUpdateManifest(
            version: version,
            downloadURL: URL(string: "https://example.internal/monitor.dmg")!
        )
    }
}
