# Changelog

All notable changes to this project are documented in this file. Versions
follow the newest `v*` git tag; the build number is the commit count.

## [Unreleased]

### Fixed

- Long MCP lists no longer try to scroll the whole MenuBarExtra window
  (SwiftUI sizes that into a flat strip). The panel is a normal VStack
  again; MCP rows mirror skills and tuck extras behind “查看更多”.

### Changed

- MCP version checks now read Cursor (`~/.cursor/mcp.json`) and Codex
  (`~/.codex/config.toml`) only; ZCode's config is no longer scanned.
- Component-version card badge wording and layout: title stays on the
  left, status like "6 个 MCP 可升级" on the right; orange tint only when
  upgrades exist.
- Each upgradable MCP row offers a copyable Terminal command: pinned
  npx packages bump `package@old` in the IDE config; resolved npm
  packages use `npm install -g` (absolute Cursor nvm paths use that
  node's npm — `skynet mcp install` often no-ops or hits pending builds).
  Missing configured binaries are called out instead of a misleading
  "node vX" badge beside a PATH-fallback version.
- Environment diagnosis now prefers `skynet mcp list -j` (falls back to
  the Chinese text parser on older CLIs), so MCP totals stay aligned with
  the CLI instead of fragile regex over layout.
- Upgradable MCP rows show a short expectation under the command buttons
  (pin rewrite / npm --prefix / bare npm / `skynet mcp install` last
  resort), so common no-ops and pending-build failures are not a surprise.
- Absolute Cursor/Codex nvm paths are compared to the login-shell
  `command -v node`; a mismatch shows in the row detail and offers one
  "改配置到 PATH Node" command per IDE (rewrites frozen nvm dirs).
- Component Skill checks prefer `skynet skill list --json` for installed
  versions (lock file is fallback), matching Environment Doctor's
  inventory; captions clarify Skill = installed vs platform, Doctor =
  installed vs team lock. README documents the session-token exception
  used only for the platform Skill API, and that expiry remains a
  heuristic until CLI grows `auth status --json` with expires.

## [0.9.0] - 2026-08-26

### Added

- "检查更新" is live: the panel queries this project's GitHub Releases
  (the release workflow attaches a DMG to every `v*` tag) and offers the
  download when a newer version exists.
- The first notification after a do-not-disturb window expires now
  carries a "已抑制 N 条通知" summary, so nothing silently vanished
  during the pause. An explicit resume clears silently.
- Shortcuts integration via App Intents: "查询登录状态" (reads the
  persisted snapshot, instant), "立即检查登录" (one real CLI probe) and
  "切换通知勿扰" (cycles the mute window off → 30min → 1h → 4h → off)
  are available in the Shortcuts app for automations and keyboard
  triggers. The settings section lists the available actions.

### Changed

- CI now installs swiftlint and fails on warnings (`--strict`), keeping
  the local pre-commit bar and the pipeline identical.

### Fixed

- SemanticVersion now parses pre-release ("1.2.0-beta") and build
  metadata ("+build.7") suffixes: a pre-release no longer compares as
  newer than its own release, which previously masked upgrade prompts.
- MCP configs that exist but cannot be read or parsed are logged with
  their path instead of silently counting as "no servers configured".

## [0.8.0] - 2026-08-24

### Added

- New `skynet-status` command-line exit: prints the last persisted check
  result and session-expiry estimate as JSON (exit 0), with distinct exit
  codes when no status exists yet (1) or on internal errors (2). Read-only
  — no CLI probes, no notifications. The packaged app now bundles it at
  `Contents/MacOS/skynet-status`; bare copies fall back to the app's
  defaults domain automatically.
- Do-not-disturb: the settings section offers "暂停通知" presets (30
  minutes / 1 hour / 4 hours). While the window is active every
  notification is dropped (checks and panel updates continue); it
  survives relaunches, expires automatically, and can be resumed early.
- Optional menu-bar countdown ("2h10m") next to the status icon while
  authenticated and an expiry estimate exists, enabled via a settings
  toggle; refreshed once a minute.
- A successful login automatically re-runs the component-version check
  when it was waiting for login, instead of keeping the needs-login hint
  until a manual recheck.
- The last component-version result is persisted and shown immediately
  on launch (with its check time) while a fresh check runs; completed
  login checks also piggyback a re-check at most once every two hours.
- npx-pinned MCP entries whose pin fell behind offer "复制新版本号" and
  a Finder reveal of the config file — the CLI's update tools cannot
  edit the ZCode config pin.
- Skill update failures now show a reason; a check that resolved zero
  skills is reported as failed instead of "all current".

### Fixed

- SemanticVersion now parses pre-release ("1.2.0-beta") and build
  metadata ("+build.7") suffixes: a pre-release no longer compares as
  newer than its own release, which previously masked upgrade prompts.
- MCP configs that exist but cannot be read or parsed are logged with
  their path instead of silently counting as "no servers configured".

### Added

- MCP version checking now also reads Cursor's ~/.cursor/mcp.json; the
  same server wired into both IDEs shows as two findings tagged by
  source, since each config can pin a different version.
- A notification fires once per "fell behind" episode when skills or
  MCPs drift (re-armed by a fully clean check).
- HTTP clients are covered by URLProtocol tests (session cookie, list
  pagination, endpoint order and fallback).

### Fixed

- Registry lookup URLs no longer double-encode the scoped package name
  ("%2F" was being sent as "%252F"; the registries happened to tolerate
  it).
- Registry endpoints now lead with the ~/.npmrc default registry before
  the built-in Skynet mirrors.

### Changed

- Skill update checks page through the platform's list endpoint (up to
  500 per request) and only fall back to per-skill detail calls for
  names the list did not cover — roughly 56 requests become ~3.
- The "检查更新" row is hidden while no update manifest URL is
  configured (`AppConfiguration.updateManifestURL` is now optional), so
  the panel no longer offers a check that can only fail.
- Long skill names in the "组件版本" card wrap to two lines with
  middle truncation instead of a clipped single line.
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
