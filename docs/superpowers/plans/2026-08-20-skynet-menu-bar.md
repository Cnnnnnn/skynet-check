# Skynet Login Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal SwiftUI menu bar app that checks the installed Skynet CLI login state and conservatively notifies when authentication expires.

**Architecture:** A Swift Package separates a testable `SkynetMonitorCore` library from the `SkynetLoginMonitor` SwiftUI executable. Core code discovers and invokes the CLI, parses Chinese/English output behind a replaceable adapter, coordinates state transitions, and sends notifications; the executable composes Apple-framework adapters and renders the menu.

**Tech Stack:** Swift 6, SwiftUI `MenuBarExtra`, AppKit, Foundation `Process`, Network, UserNotifications, ServiceManagement, Swift Package Manager, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-20-skynet-menu-bar-design.md`

## Global Constraints

- Deployment target: macOS 13.0.
- Swift tools version: 6.0 or newer.
- External package dependencies: none.
- Never read `~/.skynet-cli/session.json` or persist raw CLI output.
- Status timeout: 8 seconds; polling interval: 15 minutes; confirmation delay: 30 seconds.
- An unavailable network must never be classified as expired authentication.
- Finder launch must work without inheriting terminal/NVM `PATH`.
- Text parsing must stay behind `SkynetAuthChecking` so JSON can replace it later.

## File Map

```text
Package.swift
.gitignore
Sources/SkynetMonitorCore/
  Models/LoginState.swift
  CLI/CommandRunner.swift
  CLI/CLIPathLocator.swift
  Auth/AuthOutputParser.swift
  Auth/SkynetAuthChecker.swift
  Monitoring/LoginTransitionTracker.swift
  Monitoring/MonitorStore.swift
  System/NetworkMonitor.swift
  System/LoginNotifier.swift
  System/LaunchAtLoginController.swift
Sources/SkynetLoginMonitor/
  SkynetLoginMonitorApp.swift
  MenuBarView.swift
Tests/SkynetMonitorCoreTests/
  AuthOutputParserTests.swift
  CommandRunnerTests.swift
  CLIPathLocatorTests.swift
  LoginTransitionTrackerTests.swift
  MonitorStoreTests.swift
Packaging/Info.plist
scripts/package-app.sh
scripts/install-local.sh
README.md
```

---

### Task 1: Package Foundation and Output Parsing

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/SkynetMonitorCore/Models/LoginState.swift`
- Create: `Sources/SkynetMonitorCore/Auth/AuthOutputParser.swift`
- Create: `Sources/SkynetLoginMonitor/SkynetLoginMonitorApp.swift`
- Create: `Tests/SkynetMonitorCoreTests/AuthOutputParserTests.swift`

**Interfaces:**
- Consumes: current Chinese and English `skynet auth status` output.
- Produces: `LoginState`, `AuthOutput`, and `AuthOutputParser.parse(_:)`.

- [ ] **Step 1: Create the package skeleton**

Use this manifest shape:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkynetLoginMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SkynetMonitorCore", targets: ["SkynetMonitorCore"]),
        .executable(name: "SkynetLoginMonitor", targets: ["SkynetLoginMonitor"]),
    ],
    targets: [
        .target(name: "SkynetMonitorCore"),
        .executableTarget(name: "SkynetLoginMonitor", dependencies: ["SkynetMonitorCore"]),
        .testTarget(name: "SkynetMonitorCoreTests", dependencies: ["SkynetMonitorCore"]),
    ]
)
```

Ignore `.build/`, `build/`, and `.DS_Store`; do not ignore `.serena/` because it is already untracked user/tool metadata and must remain untouched.

Add a compile-only executable entry point so package tests can run before the real menu UI is introduced:

```swift
@main
enum SkynetLoginMonitorPlaceholder {
    static func main() {}
}
```

- [ ] **Step 2: Write failing parser tests**

Test these exact cases:

```swift
XCTAssertEqual(
    AuthOutputParser.parse(.init(
        stdout: "🔍 认证状态: 已认证\n🔍 用户邮箱: user@example.com",
        stderr: "", exitCode: 0, timedOut: false
    )),
    .authenticated(email: "user@example.com")
)
XCTAssertEqual(
    AuthOutputParser.parse(.init(
        stdout: "Authentication Status: Authenticated\nUser Email: user@example.com",
        stderr: "", exitCode: 0, timedOut: false
    )),
    .authenticated(email: "user@example.com")
)
XCTAssertEqual(
    AuthOutputParser.parse(.init(
        stdout: "使用 'skynet auth login' 进行登录",
        stderr: "", exitCode: 0, timedOut: false
    )),
    .unauthenticated
)
XCTAssertEqual(
    AuthOutputParser.parse(.init(
        stdout: "Authentication Status: Not Authenticated",
        stderr: "", exitCode: 0, timedOut: false
    )),
    .unauthenticated
)
XCTAssertEqual(
    AuthOutputParser.parse(.init(
        stdout: "unexpected", stderr: "", exitCode: 0, timedOut: false
    )),
    .serviceError(message: "Unrecognized Skynet CLI response")
)
```

- [ ] **Step 3: Run the tests and confirm the red state**

Run `swift test --filter AuthOutputParserTests`.

Expected: compilation fails because the model and parser do not exist.

- [ ] **Step 4: Implement the minimal model and parser**

Define:

```swift
public enum LoginState: Equatable, Sendable {
    case checking
    case authenticated(email: String?)
    case unauthenticated
    case offline
    case serviceError(message: String)
    case cliMissing
}

public struct AuthOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let timedOut: Bool
}

public enum AuthOutputParser {
    public static func parse(_ output: AuthOutput) -> LoginState
}
```

Parser precedence is timeout, an exact normalized authentication-status value, login prompt, abnormal exit, unrecognized output. Parse the full value after `认证状态:` or `Authentication Status:` so `Not Authenticated` cannot match `Authenticated` by substring. Extract email from `用户邮箱:` or `User Email:`; return `nil` when absent. Never include stdout/stderr in returned error text.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift test --filter AuthOutputParserTests
swift test
git diff --check
git add Package.swift .gitignore Sources Tests/SkynetMonitorCoreTests/AuthOutputParserTests.swift
git commit -m "feat: add Skynet auth output adapter"
```

Expected: tests pass and the commit contains only Task 1 files.

---

### Task 2: CLI Discovery, Timeout, and Authentication Checker

**Files:**
- Create: `Sources/SkynetMonitorCore/CLI/CommandRunner.swift`
- Create: `Sources/SkynetMonitorCore/CLI/CLIPathLocator.swift`
- Create: `Sources/SkynetMonitorCore/Auth/SkynetAuthChecker.swift`
- Create: `Tests/SkynetMonitorCoreTests/CommandRunnerTests.swift`
- Create: `Tests/SkynetMonitorCoreTests/CLIPathLocatorTests.swift`

**Interfaces:**
- Consumes: `AuthOutputParser.parse(_:)`.
- Produces: `CommandRunning`, `CLIPathLocating`, and `SkynetAuthChecking`.

- [ ] **Step 1: Write failing process and locator tests**

Create temporary executable fixtures with POSIX mode `0700`. Verify a fixture that prints `ready` returns exit code 0, and a fixture that runs `sleep 5` returns `timedOut == true` with a 100 ms timeout. For the locator, inject a fake runner and isolated `UserDefaults(suiteName: UUID().uuidString)!`; verify a valid cached absolute path wins and missing/non-executable paths produce `CLIPathError.notFound`.

- [ ] **Step 2: Run focused tests and confirm the red state**

Run:

```bash
swift test --filter CommandRunnerTests
swift test --filter CLIPathLocatorTests
```

Expected: compilation fails because runner and locator interfaces do not exist.

- [ ] **Step 3: Implement the process boundary**

Define:

```swift
public struct CommandResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let timedOut: Bool
}

public protocol CommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> CommandResult
}

public actor ProcessCommandRunner: CommandRunning {}
```

Configure `Process` with separate pipes. Race termination against `Task.sleep(for: timeout)`; when timeout wins, call `terminate()`, wait for termination, and return `timedOut: true`. Read pipes after termination and never print captured output.

- [ ] **Step 4: Implement discovery and checking**

Define:

```swift
public enum CLIPathError: Error, Equatable { case notFound }

public protocol CLIPathLocating: Sendable {
    func locate() async throws -> URL
}

public protocol SkynetAuthChecking: Sendable {
    func check(networkAvailable: Bool) async -> LoginState
    func login(networkAvailable: Bool) async -> LoginState
    func version() async -> String?
}
```

`CLIPathLocator` first validates the cached `resolvedSkynetCLIPath`; otherwise it runs `/bin/zsh -lic 'command -v skynet'` and validates an absolute executable result. Do not enumerate NVM versions.

`SkynetAuthChecker` prepends the resolved CLI directory to `/usr/bin:/bin:/usr/sbin:/sbin`, then runs:

- `auth status` with 8-second timeout;
- `auth login` with 60-second timeout, followed by status;
- `--version` with 3-second timeout.

Map lookup failure to `.cliMissing`. Map timeout/unrecognized failure to `.offline` when `networkAvailable == false`; otherwise delegate to the parser.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift test
git diff --check
git add Sources/SkynetMonitorCore/CLI Sources/SkynetMonitorCore/Auth/SkynetAuthChecker.swift Tests/SkynetMonitorCoreTests
git commit -m "feat: check Skynet CLI authentication"
```

Expected: runner, locator, and parser tests pass without reading the real session file.

---

### Task 3: Confirmation State, Scheduling, Network, and Notification

**Files:**
- Create: `Sources/SkynetMonitorCore/Monitoring/LoginTransitionTracker.swift`
- Create: `Sources/SkynetMonitorCore/Monitoring/MonitorStore.swift`
- Create: `Sources/SkynetMonitorCore/System/NetworkMonitor.swift`
- Create: `Sources/SkynetMonitorCore/System/LoginNotifier.swift`
- Create: `Tests/SkynetMonitorCoreTests/LoginTransitionTrackerTests.swift`
- Create: `Tests/SkynetMonitorCoreTests/MonitorStoreTests.swift`

**Interfaces:**
- Consumes: `SkynetAuthChecking` and `LoginState`.
- Produces: `LoginTransitionTracker`, `NetworkMonitoring`, `LoginNotifying`, and `MonitorStore`.

- [ ] **Step 1: Write failing transition tests**

Assert:

```swift
var tracker = LoginTransitionTracker()
XCTAssertEqual(tracker.consume(.unauthenticated), .confirmAfter(seconds: 30))
XCTAssertEqual(tracker.consume(.unauthenticated), .notifyExpired)
XCTAssertEqual(tracker.consume(.unauthenticated), .none)
XCTAssertEqual(tracker.consume(.authenticated(email: nil)), .none)
XCTAssertEqual(tracker.consume(.unauthenticated), .confirmAfter(seconds: 30))
```

A sequence `unauthenticated -> offline -> unauthenticated` must return `confirmAfter` twice and never `notifyExpired`.

- [ ] **Step 2: Run transition tests and confirm the red state**

Run `swift test --filter LoginTransitionTrackerTests`.

Expected: compilation fails because transition types do not exist.

- [ ] **Step 3: Implement the reducer and system protocols**

Define:

```swift
public enum LoginTransitionAction: Equatable, Sendable {
    case none
    case confirmAfter(seconds: Int)
    case notifyExpired
}

public struct LoginTransitionTracker: Sendable {
    public init() {}
    public mutating func consume(_ state: LoginState) -> LoginTransitionAction
}

public protocol NetworkMonitoring: AnyObject {
    var isAvailable: Bool { get }
    func start(onChange: @escaping @Sendable (Bool) -> Void)
    func stop()
}

public protocol LoginNotifying: Sendable {
    func requestAuthorization() async
    func notifyLoginExpired() async
}
```

`NetworkMonitor` wraps `NWPathMonitor` and emits only availability transitions. `LoginNotifier` uses identifier `skynet-login-expired`, title `Skynet 登录已失效`, and body `请重新登录，以免 CLI 任务执行时中断。`; remove a previous pending request with the same identifier before adding.

- [ ] **Step 4: Write store tests and implement the observable coordinator**

Use actor-backed fake checker/notifier and injected sleep closures. Test initial check, one in-flight check plus one coalesced refresh, 30-second confirmation without wall-clock waiting, one notification per failure episode, network recovery refresh, and authenticated recovery rearming.

Expose:

```swift
@MainActor
public final class MonitorStore: ObservableObject {
    @Published public private(set) var state: LoginState = .checking
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var cliVersion: String?
    @Published public private(set) var isChecking = false

    public func start() async
    public func refresh() async
    public func login() async
    public func handleWake()
    public func stop()
}
```

Make `start()` idempotent. Own and cancel the 15-minute periodic task and 30-second confirmation task. A trigger received during a check sets one pending bit; after completion, run exactly one additional check.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift test --filter LoginTransitionTrackerTests
swift test --filter MonitorStoreTests
swift test
git diff --check
git add Sources/SkynetMonitorCore/Monitoring Sources/SkynetMonitorCore/System Tests/SkynetMonitorCoreTests
git commit -m "feat: coordinate login checks and notifications"
```

Expected: tests complete without real 30-second or 15-minute waits.

---

### Task 4: Menu Bar UI, Wake Handling, and Launch at Login

**Files:**
- Create: `Sources/SkynetMonitorCore/System/LaunchAtLoginController.swift`
- Modify: `Sources/SkynetLoginMonitor/SkynetLoginMonitorApp.swift`
- Create: `Sources/SkynetLoginMonitor/MenuBarView.swift`

**Interfaces:**
- Consumes: `MonitorStore` and `LoginState`.
- Produces: the visible `MenuBarExtra` application and login-item controller.

- [ ] **Step 1: Add the launch-at-login adapter**

Wrap `SMAppService.mainApp.status`, `register()`, and `unregister()` behind:

```swift
@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
```

Map `.requiresApproval` to a visible explanatory status instead of reporting the toggle as enabled. Verify the imported API signatures against the local macOS 26.5 SDK at compile time; do not introduce a legacy helper or LaunchAgent fallback.

- [ ] **Step 2: Implement exhaustive status presentation**

Map states exactly:

```swift
case .checking:
    ("正在检查", "circle.dotted", Color.secondary)
case .authenticated:
    ("已登录", "checkmark.circle.fill", Color.green)
case .unauthenticated:
    ("登录已失效", "exclamationmark.circle.fill", Color.red)
case .offline:
    ("网络不可用", "wifi.exclamationmark", Color.yellow)
case .serviceError:
    ("暂时无法检查", "wifi.exclamationmark", Color.yellow)
case .cliMissing:
    ("未找到 Skynet CLI", "questionmark.circle", Color.secondary)
```

The menu shows status, optional email, CLI version, last-check time, Check Now, Log In, Launch at Login, and Quit. Disable actions while checking; disable Log In for `.cliMissing`.

- [ ] **Step 3: Compose the app and wake observer**

Create one `@StateObject MonitorStore` from concrete runner, locator, checker, network monitor, and notifier. Use `MenuBarExtra(...).menuBarExtraStyle(.menu)`. Start the store once with `.task`. Wrap `NSWorkspace.didWakeNotification` and call `store.handleWake()`.

- [ ] **Step 4: Compile, test, and smoke the executable**

Run:

```bash
swift build
swift test
swift run SkynetLoginMonitor
```

Expected: Swift 6 strict-concurrency build succeeds, one menu icon appears, current account is shown, Check Now works, and Quit terminates the process. Stop any leftover smoke process before continuing.

- [ ] **Step 5: Commit the app UI**

Run:

```bash
git diff --check
git add Sources/SkynetMonitorCore/System/LaunchAtLoginController.swift Sources/SkynetLoginMonitor
git commit -m "feat: add Skynet menu bar experience"
```

---

### Task 5: App Bundle, Local Installation, and Final Verification

**Files:**
- Create: `Packaging/Info.plist`
- Create: `scripts/package-app.sh`
- Create: `scripts/install-local.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: the release executable.
- Produces: `build/Skynet Login Monitor.app`, deliberate local installation, and operating instructions.

- [ ] **Step 1: Create the property list**

Set:

```xml
<key>CFBundleExecutable</key><string>SkynetLoginMonitor</string>
<key>CFBundleIdentifier</key><string>io.skynet.login-monitor</string>
<key>CFBundleName</key><string>Skynet Login Monitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
```

Use a complete XML plist with the Apple plist doctype.

- [ ] **Step 2: Implement and syntax-check packaging**

`scripts/package-app.sh` must use `set -euo pipefail`, resolve its repository root, build the release product, replace only the explicit bundle under `build/`, copy the executable/plist, and run:

```bash
/usr/bin/codesign --force --deep --sign - "build/Skynet Login Monitor.app"
/usr/bin/codesign --verify --deep --strict "build/Skynet Login Monitor.app"
```

Validate source and target paths are under the repository root before replacement. Run `/bin/bash -n scripts/package-app.sh` and `plutil -lint Packaging/Info.plist`.

- [ ] **Step 3: Implement the explicit installer**

`scripts/install-local.sh` prints absolute source/destination and requires interactive `y` before copying to `/Applications/Skynet Login Monitor.app`. It accepts only `--fix-permissions`.

Use task-specific `SKYNET_MONITOR_CONFIG_DIR`, defaulting to the current user's `.skynet-cli`. Without the flag, report broad modes without changes. With the flag, apply directory mode `700` and existing `session.json`/`config.json` mode `600`; skip missing files and never print contents. Run `/bin/bash -n scripts/install-local.sh`.

- [ ] **Step 4: Package and perform bounded manual checks**

Run:

```bash
swift test
swift build -c release
scripts/package-app.sh
plutil -p "build/Skynet Login Monitor.app/Contents/Info.plist"
codesign --verify --deep --strict "build/Skynet Login Monitor.app"
open "build/Skynet Login Monitor.app"
```

Verify Finder launch, no Dock icon, current account display, Check Now, offline/recovery without false notification, Log In, Launch at Login status, and Quit. Inspect bounded application logs and confirm no token, session JSON, or raw CLI output is recorded.

- [ ] **Step 5: Document, verify, and commit**

README must cover requirements, packaging, installation, uninstall, disabling Launch at Login before deletion, state meanings, and optional permission repair. Then run:

```bash
swift test
swift build -c release
scripts/package-app.sh
git diff --check
git status --short
```

Expected: tests/build/signature checks pass and only intentional files are changed. Commit:

```bash
git add Packaging scripts README.md
git commit -m "build: package Skynet login monitor app"
```

## Completion Criteria

- Finder-launched app shows the current Skynet authentication state.
- Offline/service failure remains distinct from expired login.
- Expiry notification requires two consecutive unauthenticated checks and fires once per episode.
- Check Now, Log In, Launch at Login, and Quit work on this Mac.
- Tests cover parsing, timeout, discovery, transition confirmation, and refresh coalescing.
- No implementation reads or logs the session token.
- Security permissions change only through the explicit installer flag.
