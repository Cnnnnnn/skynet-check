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
            [.failed, .failed, .passed]
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
