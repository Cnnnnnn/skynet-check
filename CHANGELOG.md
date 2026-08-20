# Changelog

All notable changes to this project are documented in this file. Versions
follow the newest `v*` git tag; the build number is the commit count.

## [Unreleased]

### Added

- In-app "检查更新" support: compares the installed version against a
  team-hosted manifest and links to the DMG when a newer release exists
  (manifest URL must be configured in `AppConfiguration`).

### Changed

- Menu panel split into focused card views; environment diagnostics is
  collapsed by default behind a disclosure group.
- User-facing text centralized in `MonitorText`.
- Notifications reuse stable identifiers so history no longer piles up in
  Notification Center.
- Documented that manual checks advance the expiry confirmation counter.
- Accessibility labels on panel controls.
- SwiftLint baseline configuration.

## [0.2.0] - 2026-08-21

### Added

- Colored menu bar status icon (non-template rendering): filled circle for
  authenticated, red ring for expired, yellow ring for offline, gray markers
  for checking / missing CLI.
- Panel shows the last completed check result and the next automatic check
  time.
- Notification permission status is reported in the environment diagnostics
  card, with a shortcut to System Settings when notifications are denied.
- Login state persistence: the last completed check is restored on launch
  before the first refresh replaces it.
- Unified `os_log` diagnostics under subsystem `io.skynet.login-monitor`
  (categories: store, runner, notifier, cli). Command output is never logged.
- CHANGELOG and git-tag-derived versioning (`scripts/app-version.sh`).

### Fixed

- Concurrent pipe draining and SIGTERM→SIGKILL escalation in the command
  runner, removing a potential deadlock with large CLI output or children
  that ignore SIGTERM.
- Login flow timeout extended to 5 minutes so browser-based authentication
  is no longer cut off.
- The first check now waits for the initial network path instead of
  assuming the network is unavailable at cold start.
- CLI resolution probes well-known install locations before a possibly
  stale cached path, and ranks nvm node versions numerically.
- `serviceError` surfaces the first stderr line (in memory only) for
  troubleshooting; persisted snapshots strip the detail.
- Login shell discovery prefers non-interactive `zsh -l -c` and only falls
  back to an interactive shell when needed.

## [0.1.0]

### Added

- Initial menu bar app: authenticated / expired / offline / missing-CLI
  states, two-check confirmation before expiry notifications, manual check
  and re-login actions with result notifications.
- Periodic checks (configurable 3–60 minutes), wake and network-recovery
  refresh triggers, launch-at-login toggle.
- Missing-CLI setup card with copyable install commands.
- Environment diagnostics, `~/.skynet-cli` permission audit and repair.
- Local ad-hoc packaging and Developer ID team release scripts with
  notarization.
