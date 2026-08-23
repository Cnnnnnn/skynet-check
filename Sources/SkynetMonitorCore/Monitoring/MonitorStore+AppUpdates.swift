import Foundation

// App self-update check and the diagnostics report. Split from
// MonitorStore.swift to keep each file focused; these members share the
// store's MainActor state by design.
extension MonitorStore {
    public func checkForUpdates() async {
        guard let updateChecker else {
            return
        }
        updateStatus = .checking
        do {
            let manifest = try await updateChecker.latestRelease()
            let status = AppUpdateEvaluator.evaluate(
                currentVersion: currentAppVersion ?? "",
                manifest: manifest
            )
            updateStatus = status
            if case .available = status {
                availableUpdate = manifest
            } else {
                availableUpdate = nil
            }
            MonitorLog.store.info(
                "update check finished: \(status.logLabel, privacy: .public)"
            )
        } catch {
            updateStatus = .failed
            availableUpdate = nil
            MonitorLog.store.error(
                "update check failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // No manifest URL configured means "检查更新" can only ever fail; the
    // panel hides the row instead.
    public var showsUpdateCheck: Bool {
        updateChecker != nil
    }

    public func diagnosticsReport() -> String {
        DiagnosticsComposer.compose(
            appVersion: currentAppVersion,
            state: state,
            lastCheckedAt: lastCheckedAt,
            lastCompletedState: lastCompletedState,
            sessionExpiresAt: sessionExpiresAt,
            sessionExpiryOutlived: sessionExpiryOutlived,
            pollingIntervalMinutes: pollingIntervalMinutes,
            notificationPermission: notificationPermission,
            permissionAudit: permissionAudit,
            environment: environmentReport,
            tokenValidation: tokenValidation,
            checkDurations: checkDurations,
            skynetConfig: skynetConfig,
            networkStability: networkStability,
            skillUpdatePhase: skillUpdatePhase,
            skillUpdateReport: skillUpdateReport,
            mcpVersionFindings: mcpVersionFindings
        )
    }
}
