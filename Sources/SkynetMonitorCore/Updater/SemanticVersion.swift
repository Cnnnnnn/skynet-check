import Foundation

struct SemanticVersion: Comparable, Sendable {
    let numbers: [Int]
    // Semver: a pre-release (1.2.0-beta) sorts *before* the release
    // (1.2.0). The flag only breaks ties when the numeric cores are
    // equal — the app never orders two different prereleases.
    let isPrerelease: Bool

    init?(_ rawValue: String) {
        var value = rawValue
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value = String(value.dropFirst())
        }

        // Everything after "-" (pre-release) or "+" (build metadata) does
        // not participate in the numeric comparison.
        if let dash = value.firstIndex(of: "-") {
            isPrerelease = true
            value = String(value[..<dash])
        } else if let plus = value.firstIndex(of: "+") {
            isPrerelease = false
            value = String(value[..<plus])
        } else {
            isPrerelease = false
        }

        let digits = value.split { !$0.isNumber }.map { Int($0) ?? 0 }
        guard !digits.isEmpty else {
            return nil
        }
        self.numbers = digits
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        for (lhsPart, rhsPart) in zip(lhs.numbers, rhs.numbers)
        where lhsPart != rhsPart {
            return lhsPart < rhsPart
        }
        // Numeric prefixes agree: the longer version wins ("1.0.0" >
        // "1.0"), matching how registries pad release triples.
        if lhs.numbers.count != rhs.numbers.count {
            return lhs.numbers.count < rhs.numbers.count
        }
        // Same numeric core: a pre-release sorts before its release.
        return lhs.isPrerelease && !rhs.isPrerelease
    }
}
