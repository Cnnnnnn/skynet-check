# Changelog

All notable changes to this project are documented in this file. Versions
follow the newest `v*` git tag; the build number is the commit count.

## [Unreleased]

### Changed

- The "组件版本" card keeps the first three upgradable skills visible and
  folds the rest behind a "查看更多" disclosure inside the card.

## [0.7.0] - 2026-08-21

### Added

- New "组件版本" panel card and diagnostics lines: skills pinned in the
  team lock are compared against the Skynet platform's main versions, and
  configured MCP servers (npx version pins and global binaries) against
  the internal npm registries. Detection only — upgrade actions hand off
  to `skynet update tools` / `skynet skill install <name>@latest`, and
  the skill check defers to the login state.

### Changed

- Past session-expiry estimates no longer look like a live deadline:
  the panel shows "估算已过期 · 以 CLI 为准", diagnostics say the same,
  and "即将/马上过期" notifications are suppressed once the estimate
  is already behind wall-clock.
- Sessions that outlive the shortest historical sample raise that lower
  bound live; the panel then shows "已超过历史最短估算 · 以 CLI 为准"
  instead of a frozen past clock.
- Panel caption clarifies monitoring is CLI-only, not the web login page.
- Expiring notifications use softer copy (confirm / optional re-login)
  instead of urging an immediate re-login.

## [0.6.0] - 2026-08-21

### Fixed

- The notification authorization prompt no longer blocks startup; the
  first check and network monitoring run while the prompt is pending.
- Action buttons span the full panel width and the token copy button uses
  a bordered style.
- Waking from sleep resets the periodic timer, avoiding an immediate
  duplicate check alongside the deferred wake refresh.

### Added

- Login URL streams out while the login command runs, so the manual
  "打开登录页面" fallback appears immediately instead of after a failure.
- Tapping a notification body now performs its most useful action
  (re-login for expiry alerts, re-check for manual results).
- Diagnostics report includes CLI check durations, the Skynet CLI config
  summary (mode/role/language), and 24h network outage history.
- "重置会话统计" action to discard corrupted session-duration samples.
- Token card and settings section collapse into disclosure groups to keep
  the panel compact.

## [0.5.0] - 2026-08-21

### Added

- Service tokens that turn invalid trigger a system notification (once per
  failure episode).
- Panel shows observed session duration statistics ("平均会话 X 小时").
- MCP configuration findings offer a "用 Terminal 修复" shortcut running
  `skynet update tools`.
- When the login flow does not finish, the panel offers an "打开登录页面"
  button with the URL the CLI printed, as a manual fallback when no
  browser opened.

### Changed

- Startup: the first login check no longer waits behind the environment
  probes; version and diagnostics run concurrently, and the probes
  themselves run in parallel (diagnostics now take the slowest probe, not
  their sum).

## [0.4.0] - 2026-08-21

### Added

- Environment diagnostics now cover CLI registry updates (with a Terminal
  upgrade shortcut), the `skynet-base` binary, MCP configuration (core MCP
  missing per IDE), installed Skills, and Skills outdated against the team
  lock baseline (with a Terminal sync shortcut).
- Predictive session-expiry warnings estimated from observed login periods
  (60/15-minute two-stage alerts).
- "复制诊断" button producing a plain-text diagnostics report.
- Service token card: Confluence (and other future service) tokens stored
  by the CLI can be copied from the panel; values are masked on screen and
  kept out of logs, diagnostics, and persistence. The Confluence token is
  validated against the REST API during diagnostics (valid / expired /
  unknown badge and diagnostics line).

## [0.3.0] - 2026-08-21

### Added

- In-app "检查更新" support: compares the installed version against a
  team-hosted manifest and links to the DMG when a newer release exists
  (manifest URL must be configured in `AppConfiguration`).

### Changed

- Wake-triggered checks wait a few seconds (default 3) for networking to
  settle instead of immediately misreporting "offline"; repeated wake
  notifications coalesce into one deferred check.
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
