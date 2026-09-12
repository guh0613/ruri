import Foundation

/// A message remains data until a presentation boundary chooses a language.
/// Only these value types can cross a task or be recorded in a session.
public struct LocalizedMessage: Codable, Equatable, Sendable {
    public enum Argument: Codable, Equatable, Sendable {
        case text(String)
        case integer(Int64)
        case decimal(Double)
        indirect case message(LocalizedMessage)

        fileprivate func value(in context: LocalizationContext) -> any CVarArg {
            switch self {
            case .text(let value): value as NSString
            case .integer(let value): value
            case .decimal(let value): value
            case .message(let value): context.string(value) as NSString
            }
        }
    }

    public let key: String
    public let table: String
    public let fallback: String
    public let arguments: [Argument]

    public init(key: String, table: String, fallback: String, arguments: [Argument] = []) {
        self.key = key; self.table = table; self.fallback = fallback; self.arguments = arguments
    }

    public static func verbatim(_ text: String) -> Self {
        .init(key: "", table: "", fallback: text)
    }

    public var localized: String { LocalizationContext.current.string(self) }

    /// Keep application-generated substitutions localizable when a composed
    /// message is saved or passed to another process.
    public func withTextArgument(_ index: Int, message: LocalizedMessage) -> Self {
        guard arguments.indices.contains(index) else { return self }
        switch arguments[index] {
        case .text, .message:
            var values = arguments; values[index] = .message(message)
            return .init(key: key, table: table, fallback: fallback, arguments: values)
        default: return self
        }
    }

    /// Store a bounded, redacted descriptor plus readable text for old readers
    /// and future readers that no longer recognize this message's identity.
    public func recorded(limit: Int = 8192, redact: (String) -> String = { $0 }) -> Self {
        let clean = redacted { String(redact($0).prefix(limit)) }
        return .init(key: key, table: table, fallback: String(redact(localized).prefix(limit)), arguments: clean.arguments)
    }

    /// Apply the same redaction to stored arguments and fallback text as to logs.
    /// Format tokens are never accepted from external data as catalog entries.
    public func redacted(_ transform: (String) -> String) -> Self {
        .init(key: key, table: table, fallback: transform(fallback), arguments: arguments.map {
            switch $0 {
            case .text(let value): .text(transform(value))
            case .message(let value): .message(value.redacted(transform))
            default: $0
            }
        })
    }

    func format(_ value: String, context: LocalizationContext) -> String {
        guard !arguments.isEmpty else { return value.replacingOccurrences(of: "%%", with: "%") }
        return String(format: value, locale: context.formatLocale, arguments: arguments.map { $0.value(in: context) })
    }
}
