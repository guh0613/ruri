import Foundation

/// Credentials are never serialized with a session. Additional masking covers
/// common authentication fields in errors and copied game reports.
public struct GameLogRedactor: Sendable {
    private var secrets: [String] = []
    private static let patterns = [
        #"(?i)(--(?:accessToken|session|clientId|xuid)(?:=|\s+))(?:"[^"\r\n]*(?:"|(?=\r|\n|$))|'[^'\r\n]*(?:'|(?=\r|\n|$))|[^\s,]+)"#,
        #"(?i)("(?:access_token|refresh_token|client_secret|accessToken)"\s*:\s*")[^"]*"#,
        #"(?i)([?&](?:access_token|refresh_token|client_secret|token)=)[^&#\s]+"#,
        #"(?i)(Authorization\s*:\s*Bearer\s+)[^\s]+"#
    ].map { try! NSRegularExpression(pattern: $0) }
    public init() {}
    public mutating func addSecrets(_ values: [String]) { secrets = Array(Set(secrets + values.filter { $0.count > 3 })).sorted { $0.count > $1.count } }
    public func redact(_ input: String) -> String {
        var result = input
        for secret in secrets { result = result.replacingOccurrences(of: secret, with: "<redacted>") }
        for pattern in Self.patterns {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1<redacted>")
        }
        return result
    }
}
