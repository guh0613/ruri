import RuriLocalization
import Foundation

/// Literal environment edits; no shell evaluation or variable interpolation.
public struct LaunchEnvironment: Sendable {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let value: String?
    }
    public let entries: [Entry]
    static let javaKeys: Set<String> = ["JAVA_HOME", "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "CLASSPATH"]
    public init(_ text: String) throws {
        guard text.utf8.count <= 65536, !text.contains("\0") else { throw RuriError.message(Messages.CoreLaunchEnvironment.javaKeysText1) }
        var entries: [Entry] = [], names = Set<String>()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreLaunchEnvironment.nameText1(String(describing: index + 1))) }
            guard !Self.javaKeys.contains(name) else { throw RuriError.message(Messages.CoreLaunchEnvironment.nameText2(String(describing: name))) }
            guard names.insert(name).inserted else { throw RuriError.message(Messages.CoreLaunchEnvironment.nameText3(String(describing: name))) }
            entries.append(.init(name: name, value: parts.count == 2 ? String(parts[1]) : nil))
        }
        guard entries.count <= 256 else { throw RuriError.message(Messages.CoreLaunchEnvironment.nameText4) }
        self.entries = entries
    }
    public func applying(to inherited: [String: String], java: URL) -> [String: String] {
        var environment = inherited
        for key in Self.javaKeys { environment.removeValue(forKey: key) }
        for entry in entries { environment[entry.name] = entry.value }
        environment["JAVA_HOME"] = java.deletingLastPathComponent().deletingLastPathComponent().path
        return environment
    }
}
