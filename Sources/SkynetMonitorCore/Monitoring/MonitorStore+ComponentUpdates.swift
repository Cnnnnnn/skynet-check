import Foundation

// Component-version drift detection (skills + MCP packages): checking,
// throttling, notification and card visibility. Detection only — upgrades
// stay with the CLI. Split from MonitorStore.swift to keep each file
// focused; these members deliberately share the store's MainActor state.
extension MonitorStore {
    // Compares locally installed skills/MCP packages against their remote
    // latest versions.
    public func checkComponentUpdates() async {
        pendingComponentRecheckAfterUpgrade = false
        guard skillUpdateChecker != nil || mcpVersionChecker != nil else {
            return
        }
        guard !componentUpdateInProgress else {
            return
        }
        componentUpdateInProgress = true
        skillUpdatePhase = .checking

        async let skillResult = skillUpdateChecker?.checkForUpdates()
        async let mcpResult = mcpVersionChecker?.checkVersions()
        let (skills, mcps) = await (skillResult, mcpResult)

        if let skills {
            switch skills {
            case .needsLogin:
                skillUpdatePhase = .needsLogin
                skillUpdateReport = nil
                skillUpdateFailureDetail = nil
            case let .completed(report):
                skillUpdatePhase = .completed
                skillUpdateReport = report
                skillUpdateFailureDetail = nil
            case let .failed(reason):
                skillUpdatePhase = .failed
                skillUpdateReport = nil
                skillUpdateFailureDetail = reason
            }
            MonitorLog.store.info(
                "skill update check: \(skills.logLabel, privacy: .public)"
            )
        }
        if let mcps {
            mcpVersionFindings = mcps
            MonitorLog.store.info(
                "mcp version check: \(mcps.count, privacy: .public) server(s)"
            )
        }
        componentUpdateCheckedAt = now()
        await notifyComponentUpdatesIfNeeded()
        componentUpdateStore?.save(
            ComponentUpdateSnapshot(
                savedAt: componentUpdateCheckedAt!,
                skillPhase: skillUpdatePhase,
                skillReport: skillUpdateReport,
                mcpFindings: mcpVersionFindings
            )
        )
        componentUpdateInProgress = false
    }

    public func noteComponentUpgradeCommandUsed() {
        pendingComponentRecheckAfterUpgrade = true
    }

    // Menu bar panel re-appeared after the user likely ran a pasted upgrade.
    public func recheckComponentsIfUpgradePending() async {
        guard pendingComponentRecheckAfterUpgrade else {
            return
        }
        await checkComponentUpdates()
    }

    // One notification per "fell behind" episode; a fully clean completed
    // check re-arms it for the next drift.
    fileprivate func notifyComponentUpdatesIfNeeded() async {
        guard skillUpdatePhase == .completed else {
            return
        }
        let skillCount = skillUpdateReport?.updates.count ?? 0
        let mcpCount = mcpVersionFindings.filter(\.isUpgradable).count
        let hasUpdates = skillCount > 0 || mcpCount > 0
        if hasUpdates {
            guard !notifiedComponentUpdatesEpisode else {
                return
            }
            notifiedComponentUpdatesEpisode = true
            await notifier.notifyComponentUpdatesAvailable(
                skillCount: skillCount,
                mcpCount: mcpCount
            )
        } else {
            notifiedComponentUpdatesEpisode = false
        }
    }

    // Component versions drift on a daily cadence; piggyback on any
    // completed refresh (periodic, manual, wake, network recovery) but at
    // most once every two hours.
    fileprivate static let componentRecheckInterval: TimeInterval = 2 * 60 * 60

    func maybeRecheckComponentUpdates() {
        guard skillUpdateChecker != nil || mcpVersionChecker != nil else {
            return
        }
        if let lastChecked = componentUpdateCheckedAt,
           now().timeIntervalSince(lastChecked) < Self.componentRecheckInterval
        {
            return
        }
        Task { await checkComponentUpdates() }
    }

    // The component card appears once a check has produced anything to say;
    // stores without checkers (tests) never show it.
    public var showsComponentUpdates: Bool {
        skillUpdateChecker != nil || mcpVersionChecker != nil
    }
}
