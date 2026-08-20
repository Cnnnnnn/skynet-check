import Foundation
import XCTest
@testable import SkynetMonitorCore

final class CLIVersionCheckerTests: XCTestCase {
    func testParsesLatestVersionFromRegistryPayload() throws {
        let json = #"{"name":"@shopee/skynet-cli","version":"2.7.33"}"#

        let version = try RegistryCLIVersionChecker.parseLatestVersion(
            from: Data(json.utf8)
        )

        XCTAssertEqual(version, "2.7.33")
    }

    func testRejectsPayloadWithoutVersion() {
        let json = #"{"name":"@shopee/skynet-cli"}"#

        XCTAssertThrowsError(
            try RegistryCLIVersionChecker.parseLatestVersion(
                from: Data(json.utf8)
            )
        )
    }

    func testDetectsWhenInstalledCLIIsBehind() {
        XCTAssertTrue(
            makeReport(current: "2.7.29", latest: "2.7.33").isCLIBehindLatest
        )
        XCTAssertFalse(
            makeReport(current: "2.7.33", latest: "2.7.33").isCLIBehindLatest
        )
        XCTAssertFalse(
            makeReport(current: "2.7.33", latest: "2.7.29").isCLIBehindLatest
        )
        XCTAssertFalse(
            makeReport(current: "2.7.33", latest: nil).isCLIBehindLatest
        )
        XCTAssertFalse(
            makeReport(current: nil, latest: "2.7.33").isCLIBehindLatest
        )
    }

    func testDoctorIncludesLatestVersionWhenRegistryCheckSucceeds() async {
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: DoctorStubRunner(),
            cliVersionChecker: DoctorStubVersionChecker(latest: "2.7.33")
        )

        let report = await doctor.inspect(networkAvailable: true)

        XCTAssertEqual(report.cliVersion, "2.7.29")
        XCTAssertEqual(report.latestCLIVersion, "2.7.33")
    }

    func testDoctorToleratesRegistryFailure() async {
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: DoctorStubRunner(),
            cliVersionChecker: DoctorStubVersionChecker(error: URLError(.notConnectedToInternet))
        )

        let report = await doctor.inspect(networkAvailable: false)

        XCTAssertNil(report.latestCLIVersion)
    }

    private func makeReport(current: String?, latest: String?) -> EnvironmentReport {
        EnvironmentReport(
            cliPath: "/fake/bin/skynet",
            cliVersion: current,
            nodeVersion: "v22.23.2",
            networkAvailable: true,
            latestCLIVersion: latest
        )
    }
}

private struct DoctorStubLocator: CLIPathLocating {
    let url: URL?

    func locate() async throws -> URL {
        guard let url else {
            throw CLIPathError.notFound
        }
        return url
    }
}

private struct DoctorStubChecker: SkynetAuthChecking {
    private let version: String?

    init(version: String?) {
        self.version = version
    }

    func check(networkAvailable: Bool) async -> LoginState {
        .authenticated(email: nil)
    }

    func login(networkAvailable: Bool) async -> LoginActionResult {
        .alreadyAuthenticated(email: nil)
    }

    func version() async -> String? {
        version
    }
}

private struct DoctorStubRunner: CommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        CommandResult(stdout: "", stderr: "", exitCode: 1, timedOut: false)
    }
}

private struct DoctorStubVersionChecker: CLIVersionChecking {
    private let latest: String?
    private let error: Error?

    init(latest: String) {
        self.latest = latest
        self.error = nil
    }

    init(error: Error) {
        self.latest = nil
        self.error = error
    }

    func fetchLatest() async throws -> String {
        if let error {
            throw error
        }
        return latest!
    }
}
