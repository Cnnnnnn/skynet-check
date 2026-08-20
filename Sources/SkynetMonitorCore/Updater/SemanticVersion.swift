import Foundation

struct SemanticVersion: Comparable, Sendable {
    let numbers: [Int]

    init?(_ rawValue: String) {
        let digits = rawValue.split { !$0.isNumber }.map { Int($0) ?? 0 }
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
        return lhs.numbers.count < rhs.numbers.count
    }
}
