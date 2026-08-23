import Foundation

// Service-token validation and invalid-token alerting. Split from
// MonitorStore.swift to keep each file focused; these members share the
// store's MainActor state by design.
extension MonitorStore {
    // One notification per token per failure episode; a token that turns
    // valid again re-arms the alert.
    func notifyInvalidTokensIfNeeded() async {
        let tokenByName = Dictionary(
            serviceTokens.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (key, outcome) in tokenValidation.sorted(by: { $0.key < $1.key }) {
            switch outcome {
            case .invalid:
                guard !notifiedInvalidTokenKeys.contains(key) else {
                    continue
                }
                notifiedInvalidTokenKeys.insert(key)
                await notifier.notifyServiceTokenInvalid(
                    key: key,
                    name: tokenByName[key]?.displayName ?? key
                )
            case .valid:
                notifiedInvalidTokenKeys.remove(key)
            case .unknown:
                break
            }
        }
    }

    func validateTokens(
        _ tokens: [ServiceToken]
    ) async -> [String: ServiceTokenValidationOutcome] {
        guard let tokenValidator else {
            return [:]
        }

        // Outcomes carry no token material — only the per-key verdict.
        return await withTaskGroup(
            of: (String, ServiceTokenValidationOutcome).self
        ) { group in
            for token in tokens where tokenValidator.supportedKeys.contains(token.key) {
                group.addTask {
                    let outcome = await tokenValidator.validate(token: token)
                    MonitorLog.store.info(
                        "token \(token.key, privacy: .public) validation: \(outcome.logLabel, privacy: .public)"
                    )
                    return (token.key, outcome)
                }
            }
            var results: [String: ServiceTokenValidationOutcome] = [:]
            for await (key, outcome) in group {
                results[key] = outcome
            }
            return results
        }
    }
}
