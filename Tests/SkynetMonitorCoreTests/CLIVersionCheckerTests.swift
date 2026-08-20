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

    func testDoctorDetectsSkynetBaseFromLoginShell() async {
        let runner = DoctorStubRunner(results: [
            .succeeded(stdout: "v22.23.2\n"),
            .succeeded(stdout: "/opt/homebrew/bin/skynet-base\n"),
        ])
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: runner,
            cliVersionChecker: DoctorStubVersionChecker(latest: "2.7.33")
        )

        let report = await doctor.inspect(networkAvailable: true)

        XCTAssertEqual(report.nodeVersion, "v22.23.2")
        XCTAssertTrue(report.skynetBaseFound)
    }

    func testDoctorMarksSkynetBaseMissingWhenShellCannotFindIt() async {
        let runner = DoctorStubRunner(results: [
            .succeeded(stdout: "v22.23.2\n"),
            .failed(),
            .failed(),
        ])
        let doctor = EnvironmentDoctor(
            locator: DoctorStubLocator(url: URL(fileURLWithPath: "/fake/bin/skynet")),
            checker: DoctorStubChecker(version: "2.7.29"),
            runner: runner
        )

        let report = await doctor.inspect(networkAvailable: true)

        XCTAssertFalse(report.skynetBaseFound)
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

private actor DoctorStubRunner: CommandRunning {
    private var results: [CommandResult]

    init(results: [CommandResult] = []) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult {
        results.isEmpty ? .failed() : results.removeFirst()
    }
}

private extension CommandResult {
    static func succeeded(stdout: String) -> Self {
        CommandResult(stdout: stdout, stderr: "", exitCode: 0, timedOut: false)
    }

    static func failed() -> Self {
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
