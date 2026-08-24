# Skynet Login Monitor

A personal macOS menu bar app that checks the local Skynet CLI login state and warns after two consecutive unauthenticated results.

## Requirements

- macOS 13 or newer
- Xcode command-line tools with Swift 6
- Skynet CLI available from the interactive zsh/NVM environment

The app never reads `~/.skynet-cli/session.json` and never stores CLI output
or token material. One exception by design: service tokens the Skynet CLI
keeps in `~/.skynet-cli/tokens.json` (e.g. the Confluence token) can be
copied from the panel on demand. Token values are masked on screen, never
logged, never included in the diagnostics report, and never persisted by the
app — the CLI's file remains the single source of truth.

## Build and run

```bash
swift test
scripts/package-app.sh
open "build/Skynet Login Monitor.app"
```

The packaged app is ad-hoc signed for local use. It has no Dock icon.

## Status query for scripts

`skynet-status` prints the last persisted check result as JSON — no CLI
probes, no notifications. Exit code 0 with a report, 1 when no status
exists yet:

```bash
swift build
.build/debug/skynet-status --status --json
# {"authenticated": true, "state": "authenticated", "email": "…",
#  "checkedAt": …, "sessionExpiresAt": …}
```

Commits run swiftlint + swift test via a local pre-commit hook. Enable it
after cloning (git config is not versioned):

```bash
git config core.hooksPath scripts/githooks
```

For team distribution, run scripts/package-team-release.sh after importing a
Developer ID Application certificate and creating a notarytool keychain
profile. The script requires SKYNET_SIGNING_IDENTITY and
SKYNET_NOTARY_PROFILE; it signs, notarizes, staples, and verifies the DMG.
Never put certificate files, Apple credentials, or notarization profiles in
the repository.

## Versioning

Versions come from git tags; `Packaging/Info.plist` keeps placeholder values
that `scripts/package-app.sh` overwrites at packaging time. The marketing
version is the newest reachable `v*` tag (e.g. `v0.2.0`) and the build number
is the commit count. To cut a release, update CHANGELOG.md, commit, then tag:

```bash
git tag v0.2.1
scripts/package-team-release.sh
```

For a local, unsigned DMG (no Developer ID certificate needed):

```bash
scripts/package-app.sh && scripts/package-dmg.sh
```

## Install locally

```bash
scripts/install-local.sh
```

The installer asks before copying the app to `/Applications/Skynet Login Monitor.app`. It reports Skynet config modes without changing them.

To explicitly restrict `~/.skynet-cli` to mode `700` and existing `session.json` / `config.json` files to mode `600`:

```bash
scripts/install-local.sh --fix-permissions
```

## Status

- Green check: authenticated
- Red exclamation: login expired
- Yellow Wi-Fi: offline or the Skynet service could not be checked
- Gray question mark: Skynet CLI could not be found

The app checks on launch, every 15 minutes, after wake, and after network recovery. A login-expired notification requires two unauthenticated checks 30 seconds apart and is sent once for that failure episode.

If Skynet CLI is missing, the menu shows the documented Node.js and Skynet
installation commands, lets the user copy them, opens Terminal, and provides a
重新检测 action. The app never installs global dependencies silently.

## Menu actions

- **立即检查** runs an immediate status check and sends a macOS notification
  with the completed result. Automatic checks stay silent unless login expiry
  is confirmed.
- **重新登录** first checks the current session. An already-valid session
  produces a “无需重新登录” notification; an invalid session opens the Skynet
  browser login flow and reports the completed result.
- **开机启动** uses the macOS Login Items service.
- **暂停通知** (do-not-disturb) drops all notifications for a preset window
  (30 minutes / 1 hour / 4 hours) while checks and panel updates continue.
  The window survives relaunches, expires automatically, and can be resumed
  early from the settings section.
- **菜单栏显示剩余时间** adds a compact countdown ("2h10m") next to the
  status icon while authenticated and an expiry estimate exists.
- **Shortcuts** exposes three App Intents for automations and keyboard
  triggers: 查询登录状态 (persisted snapshot, instant), 立即检查登录 (a
  real CLI probe) and 切换通知勿扰 (cycles the mute window). Build them
  in the Shortcuts app; macOS does not support Siri voice phrases.
- **检查更新** compares the installed version against a team-hosted
  manifest (`AppConfiguration.updateManifestURL`) and opens the DMG download
  page when a newer release exists. Until the real manifest URL is configured,
  the check reports a failure instead of a false result.
- **退出** stops monitoring and closes the app.

The menu bar panel uses a compact native macOS window layout with a status
header, account metadata, primary action buttons, and a dedicated setup card
when the CLI is missing.

The panel also exposes the automatic-check interval as a slider from 3 to 60
minutes. The default is 15 minutes; changes are persisted locally and restart
the timer immediately.

## Team support matrix

- macOS 13 or newer
- Apple Silicon and Intel
- Node.js installed through Homebrew or another supported installation
- Skynet CLI installed with the team registry command shown in the missing-CLI guide
- Network access to the internal NPM registry during CLI installation

The app has no shared account or team token. Each user keeps their own Skynet
CLI session and notification permission.

## Uninstall

Turn off **开机启动** in the menu first, quit the app, and move `/Applications/Skynet Login Monitor.app` to Trash. The app does not delete or modify Skynet CLI configuration.
