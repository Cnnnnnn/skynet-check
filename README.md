# Skynet Login Monitor

A personal macOS menu bar app that checks the local Skynet CLI login state and warns after two consecutive unauthenticated results.

## Requirements

- macOS 13 or newer
- Xcode command-line tools with Swift 6
- Skynet CLI available from the interactive zsh/NVM environment

The app never reads `~/.skynet-cli/session.json` and never stores CLI output or token material.

## Build and run

```bash
swift test
scripts/package-app.sh
open "build/Skynet Login Monitor.app"
```

The packaged app is ad-hoc signed for local use. It has no Dock icon.

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
- **退出** stops monitoring and closes the app.

The menu bar panel uses a compact native macOS window layout with a status
header, account metadata, primary action buttons, and a dedicated setup card
when the CLI is missing.

## Uninstall

Turn off **开机启动** in the menu first, quit the app, and move `/Applications/Skynet Login Monitor.app` to Trash. The app does not delete or modify Skynet CLI configuration.
