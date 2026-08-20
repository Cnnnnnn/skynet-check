import Foundation

public enum AuthOutputParser {
    public static func parse(_ output: AuthOutput) -> LoginState {
        if output.timedOut {
            return .serviceError(message: "Skynet CLI timed out")
        }

        let lines = output.stdout.components(separatedBy: .newlines)
        if let status = value(in: lines, labels: ["认证状态", "Authentication Status"]) {
            switch status {
            case "已认证", "Authenticated":
                return .authenticated(
                    email: value(in: lines, labels: ["用户邮箱", "User Email"])
                )
            case "未认证", "Not Authenticated":
                return .unauthenticated
            default:
                break
            }
        }

        if output.stdout.contains("使用 'skynet auth login' 进行登录")
            || output.stdout.contains("Use 'skynet auth login' to authenticate")
        {
            return .unauthenticated
        }

        if output.exitCode != 0 {
            return .serviceError(
                message: errorDetail(
                    for: output,
                    fallback: "Skynet CLI exited with an error"
                )
            )
        }

        return .serviceError(
            message: errorDetail(
                for: output,
                fallback: "Unrecognized Skynet CLI response"
            )
        )
    }

    // Only the first stderr line is surfaced, capped in length, and kept in
    // memory for the panel; it never reaches logs or persisted snapshots.
    static func errorDetail(for output: AuthOutput, fallback: String) -> String {
        guard
            let line = output.stderr
                .components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty })
        else {
            return fallback
        }
        return String(line.prefix(120))
    }

    private static func value(in lines: [String], labels: [String]) -> String? {
        for line in lines {
            for label in labels {
                guard let range = line.range(of: label) else {
                    continue
                }

                return line[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))
            }
        }

        return nil
    }
}
