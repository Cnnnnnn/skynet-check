import Foundation

public enum LoginURLExtractor {
    // The login command prints its browser URL into stdout as a fallback
    // for environments where the browser does not open; surface the first
    // one so the panel can offer a manual link.
    public static func firstURL(in output: String) -> URL? {
        let pattern = /https?:\/\/[A-Za-z0-9._~:\/?#\[\]@!$&'()*+,;=%-]+/
        guard let match = output.firstMatch(of: pattern) else {
            return nil
        }
        return URL(string: String(match.output))
    }
}
