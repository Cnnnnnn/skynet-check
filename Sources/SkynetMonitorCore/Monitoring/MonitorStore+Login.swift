import Foundation

// The interactive login flow. Split from MonitorStore.swift to keep each
// file focused; these members share the store's MainActor state by design.
extension MonitorStore {
    public func login() async {
        guard !isChecking else {
            refreshPending = true
            return
        }

        isChecking = true
        state = .checking
        let loginResult = await checker.login(
            networkAvailable: networkMonitor.isAvailable,
            onLoginURL: { [weak self] url in
                // The URL is printed as soon as the login command starts;
                // show the manual-fallback button right away instead of
                // waiting for the whole (possibly stalled) flow.
                Task { @MainActor [weak self] in
                    self?.loginURL = url
                }
            }
        )
        let result = loginResult.state
        await complete(with: result)
        // Keep the login URL around when the flow did not finish; the
        // panel offers it as a manual fallback if no browser opened.
        loginURL = loginResult.loginURL
        MonitorLog.store.info(
            "login flow completed: \(result.presentation.title, privacy: .public)"
        )
        await handleTransition(result)
        await notifier.notifyLoginResult(loginResult)
        // A login unlocks the platform-backed skill check; re-run it right
        // away instead of leaving the panel on the needs-login hint.
        if result.isAuthenticated, skillUpdatePhase == .needsLogin {
            await checkComponentUpdates()
        }
    }
}
