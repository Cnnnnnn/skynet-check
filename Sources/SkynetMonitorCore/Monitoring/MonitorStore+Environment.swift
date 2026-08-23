import Foundation

// Environment inspection, notification-permission status and permission
// repair. Split from MonitorStore.swift to keep each file focused; these
// members share the store's MainActor state by design.
extension MonitorStore {
    public func inspectEnvironment() async {
        // Component-version checks hit the platform and npm registries and
        // can take seconds; they run beside the environment probes instead
        // of blocking them.
        if skillUpdateChecker != nil || mcpVersionChecker != nil {
            Task { await checkComponentUpdates() }
        }
        notificationPermission = await notifier.authorizationStatus()
        if let serviceTokenReader {
            // Values are published for the panel's copy action only; never
            // logged and never part of the diagnostics report.
            let tokens = serviceTokenReader.availableTokens()
            serviceTokens = tokens
            MonitorLog.store.info(
                "loaded \(tokens.count, privacy: .public) service token(s)"
            )
            tokenValidation = await validateTokens(tokens)
            await notifyInvalidTokensIfNeeded()
        }
        if let configReader {
            skynetConfig = configReader.read()
        }
        guard let environmentDoctor else {
            return
        }
        environmentReport = await environmentDoctor.inspect(
            networkAvailable: networkMonitor.isAvailable
        )
        permissionAudit = permissionManager.audit()
    }

    public func repairPermissions() {
        do {
            try permissionManager.repair()
            permissionAudit = permissionManager.audit()
            permissionRepairMessage = MonitorText.Permission.repaired
        } catch {
            permissionRepairMessage = MonitorText.Permission.repairFailed
        }
    }
}
