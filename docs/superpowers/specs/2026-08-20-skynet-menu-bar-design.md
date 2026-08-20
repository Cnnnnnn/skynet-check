# Skynet Login Monitor Menu Bar Design

## Goal

Build a personal macOS menu bar application that checks whether the locally installed Skynet CLI session is still valid and notifies the user when a previously valid login becomes invalid.

## Scope

The first release targets this Mac only. It does not include team distribution, notarization, an updater, analytics, or direct Skynet API integration.

The application must:

- run as a SwiftUI `MenuBarExtra` application on macOS 13 or newer;
- discover the Skynet CLI installed through the user's interactive zsh/NVM environment;
- invoke the existing `skynet auth status` and `skynet version` commands without reading `~/.skynet-cli/session.json`;
- represent checking, authenticated, unauthenticated, offline, service error, and CLI-missing states separately;
- check on launch, every 15 minutes, after Mac wake, and after network recovery;
- retry an unauthenticated result once after 30 seconds and notify only when both checks are unauthenticated;
- provide Check Now, Log In, Launch at Login, and Quit actions;
- avoid logging, copying, or persisting the session token;
- build into a local `.app` bundle without third-party runtime dependencies.

## Constraints

- Swift tools version: 6.0 or newer.
- Deployment target: macOS 13.0.
- UI technology: SwiftUI and AppKit only.
- System integrations: `MenuBarExtra`, `UserNotifications`, `Network`, `ServiceManagement`, and `NSWorkspace` wake notifications.
- External package dependencies: none.
- The application must work when launched from Finder, where the process does not inherit the terminal's NVM `PATH`.
- The app must treat CLI output as an adapter boundary so a future `skynet auth status --json` response can replace text parsing without changing UI or scheduling code.

## Architecture

```text
SkynetLoginMonitorApp
  -> MonitorStore
       -> CheckScheduler
       -> SkynetAuthChecking
            -> CLIPathLocator
            -> CommandRunning
            -> AuthOutputParser
       -> LoginStateMachine
       -> LoginNotifier
  -> MenuBarView
  -> LaunchAtLoginController
```

`MonitorStore` is the single observable owner of user-visible state. Infrastructure components expose small protocols so parsing, process execution, transition logic, and notification behavior can be tested without launching a menu bar application.

## CLI Discovery and Execution

On startup, `CLIPathLocator` resolves the executable in this order:

1. A previously resolved absolute path stored in `UserDefaults`, if the file still exists and is executable.
2. `/bin/zsh -lic 'command -v skynet'`, with stdout trimmed and validated as an absolute executable path.

No hard-coded NVM version path is stored in source. When invoking Skynet, `CommandRunner` prepends the resolved executable's directory to `PATH`; this makes the adjacent NVM `node` executable available to Skynet's `#!/usr/bin/env node` launcher.

Each status command has an eight-second application timeout. On timeout, the process is terminated and classified as a service error when the network is available, or offline when `NWPathMonitor` reports no usable path. Standard output and standard error are captured only in memory and are discarded after classification.

## Status Classification

`AuthOutputParser` supports the current Chinese and English CLI output:

- authenticated: output contains the authentication status label and `已认证`, or the English equivalents `Authentication Status` and `Authenticated`;
- unauthenticated: output contains `使用 'skynet auth login' 进行登录` or `Use 'skynet auth login' to authenticate`;
- error: the command times out, cannot launch, exits abnormally without a recognized authentication result, or returns unrecognized output.

Network state refines errors but does not override an explicit authenticated result. An unavailable network is shown as offline and never produces a login-expired notification.

The state model is:

```swift
enum LoginState: Equatable, Sendable {
    case checking
    case authenticated(email: String?)
    case unauthenticated
    case offline
    case serviceError(message: String)
    case cliMissing
}
```

An unauthenticated result becomes visible immediately, but notification is conservative: the state machine schedules a confirmation check after 30 seconds and sends one notification only if that check is also unauthenticated. A later authenticated result resets the failure count and allows a future authenticated-to-unauthenticated transition to notify again.

## Menu Bar Experience

The menu bar uses system symbols and color as redundant cues:

- authenticated: green `checkmark.circle.fill`;
- unauthenticated: red `exclamationmark.circle.fill`;
- offline or service error: yellow `wifi.exclamationmark`;
- checking or CLI missing: gray `circle.dotted` or `questionmark.circle`.

The menu shows the current status, authenticated email when available, CLI version when detected, and the last check time. Actions are:

- **Check Now**: starts an immediate check unless one is already running;
- **Log In**: runs `skynet auth login`, lets the CLI open the default browser, then rechecks after the login process completes;
- **Launch at Login**: registers or unregisters the packaged app with `SMAppService.mainApp`;
- **Quit**: terminates the application.

The application requests notification permission on first launch. A denied permission leaves menu status fully functional and displays no repeated permission prompts.

## Scheduling and Concurrency

`MonitorStore` runs on `@MainActor`. CLI processes execute asynchronously and return a `CommandResult`; UI state changes return to the main actor. Only one status check may run at a time. Duplicate timer, wake, network, or manual triggers while a check is active are coalesced into a single pending refresh.

The periodic interval is 15 minutes. `NSWorkspace.didWakeNotification` triggers a check after wake. `NWPathMonitor` triggers a check only when connectivity changes from unavailable to available, preventing every path update from causing a request.

## Security and Privacy

The application never opens the session file and never receives the token. It does not persist raw CLI output. Logs may contain only timestamps, command duration, resolved executable path, state category, and sanitized error category; the email is shown in memory but is not written to logs.

The local installer checks permissions without reading file contents. If `~/.skynet-cli` is broader than `700` or `session.json`/`config.json` is broader than `600`, it prints the exact repair commands. Permission changes occur only when the installer is invoked with `--fix-permissions`.

## Packaging

The repository uses Swift Package Manager for compilation and tests. `scripts/package-app.sh` builds a release executable and assembles `build/Skynet Login Monitor.app` with an `Info.plist` configured as an agent application (`LSUIElement = true`). `scripts/install-local.sh` copies the bundle into `/Applications` after confirming the exact source and destination; it supports the optional `--fix-permissions` flag described above.

The first release is locally ad-hoc signed. Notarization and automatic updates are explicitly outside scope.

## Verification

Automated XCTest coverage includes:

- Chinese and English authenticated output;
- Chinese and English unauthenticated output;
- malformed and empty output;
- CLI path discovery using controlled process results;
- timeout and abnormal process termination;
- offline refinement;
- two-failure notification confirmation and reset after recovery;
- coalescing overlapping refresh requests.

Manual verification on this Mac includes:

1. build and launch the `.app` bundle from Finder;
2. confirm CLI discovery succeeds outside the terminal environment;
3. confirm the menu reports the currently authenticated account;
4. disconnect and reconnect networking and verify offline/recovery states without an expired-login notification;
5. verify Check Now and Log In actions;
6. enable Launch at Login and confirm registration status;
7. inspect logs to confirm no token or raw CLI output is persisted.

## Future CLI Contract

When Skynet CLI provides `skynet auth status --json --no-persist --timeout 5`, only the checker/parser adapter changes. The preferred response distinguishes `authenticated`, `unauthenticated`, `offline`, and `service_error` and never includes the token. Menu UI, scheduling, transition confirmation, and notifications remain unchanged.
