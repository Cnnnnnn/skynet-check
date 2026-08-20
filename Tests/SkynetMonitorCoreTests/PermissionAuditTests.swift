import Foundation
import XCTest
@testable import SkynetMonitorCore

final class PermissionAuditTests: XCTestCase {
    func testAuditsAndRepairsOnlySkynetCredentialPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let session = root.appendingPathComponent("session.json")
        let config = root.appendingPathComponent("config.json")
        try "{}".write(to: session, atomically: true, encoding: .utf8)
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: session.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: config.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = SkynetPermissionManager(configDirectory: root)

        XCTAssertTrue(manager.audit().needsRepair)
        try manager.repair()
        let repaired = manager.audit()

        XCTAssertFalse(repaired.needsRepair)
        XCTAssertEqual(repaired.directoryMode, 0o700)
        XCTAssertEqual(repaired.sessionMode, 0o600)
        XCTAssertEqual(repaired.configMode, 0o600)
    }
}
