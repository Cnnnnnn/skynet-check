import XCTest
@testable import SkynetMonitorCore

final class EnvironmentDoctorTests: XCTestCase {
    func testReportMarksMissingCLIAndNodeAsFailures() {
        let report = EnvironmentReport(
            cliPath: nil,
            cliVersion: nil,
            nodeVersion: nil,
            networkAvailable: true
        )

        XCTAssertEqual(
            report.checks.map(\.status),
            [.failed, .failed, .passed, .passed]
        )
    }

    func testReportWarnsWhenSkynetBaseIsMissing() {
        let report = EnvironmentReport(
            cliPath: "/opt/homebrew/bin/skynet",
            cliVersion: "2.7.29",
            nodeVersion: "v22.23.2",
            networkAvailable: true,
            latestCLIVersion: nil,
            skynetBaseFound: false
        )

        XCTAssertEqual(
            report.checks.last?.status,
            .warning
        )
        XCTAssertEqual(
            report.checks.last?.detail,
            "未安装，key 功能不可用"
        )
    }

    func testReportMarksReadyEnvironmentAsPassed() {
        let report = EnvironmentReport(
            cliPath: "/opt/homebrew/bin/skynet",
            cliVersion: "2.7.29",
            nodeVersion: "22.14.0",
            networkAvailable: true
        )

        XCTAssertTrue(report.checks.allSatisfy { $0.status == .passed })
    }
}
