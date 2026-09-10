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
        guard text.utf8.count <= 65536, !text.contains("\0") else { throw RuriError.message("环境变量包含空字符或超过 64 KB。") }
        var entries: [Entry] = [], names = Set<String>()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw RuriError.message("第 \(index + 1) 行的环境变量名称无效。请使用字母、数字和下划线，且不能以数字开头。") }
            guard !Self.javaKeys.contains(name) else { throw RuriError.message("\(name) 由 Ruri 管理，请使用 Java 选择或附加 JVM 参数设置。") }
            guard names.insert(name).inserted else { throw RuriError.message("环境变量重复：\(name)") }
            entries.append(.init(name: name, value: parts.count == 2 ? String(parts[1]) : nil))
        }
        guard entries.count <= 256 else { throw RuriError.message("自定义环境变量不能超过 256 项。") }
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
