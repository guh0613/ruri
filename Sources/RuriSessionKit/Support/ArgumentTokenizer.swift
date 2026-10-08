import Foundation
import RuriLocalization

public enum ArgumentTokenizer {
    public static func join(_ arguments: [String]) -> String {
        arguments.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }.joined(separator: " ")
    }
    public static func split(_ input: String) throws -> [String] {
        var output: [String] = []; var token = ""; var quote: Character?; var escape = false; var started = false
        for c in input {
            if escape { token.append(c); escape = false; started = true; continue }
            if c == "\\", quote != "'" { escape = true; started = true; continue }
            if let q = quote { if c == q { quote = nil } else { token.append(c) }; continue }
            if c == "\"" || c == "'" { quote = c; started = true; continue }
            if c.isWhitespace { if started { output.append(token); token = ""; started = false } }
            else { token.append(c); started = true }
        }
        guard quote == nil, !escape else { throw RuriError.message(Messages.CoreLaunch.unclosedLaunchQuoting) }
        if started { output.append(token) }
        return output
    }
}

