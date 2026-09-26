import RuriLocalization
import Foundation

/// The public command boundary deliberately does not expose persistence models.
public enum OperationValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([OperationValue]), object([String: OperationValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([OperationValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: OperationValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public static func encode<T: Encodable>(_ value: T) throws -> Self {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(Self.self, from: encoder.encode(value))
    }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
    public var object: [String: Self]? { if case .object(let v) = self { v } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var int: Int? { if case .number(let v) = self, v.isFinite, v.rounded() == v, v >= Double(Int.min), v < Double(Int.max) { Int(v) } else { nil } }
    public subscript(_ key: String) -> Self { object?[key] ?? .null }
    public static func text(_ value: String?) -> Self { value.map(Self.string) ?? .null }
    public static func integer(_ value: some BinaryInteger) -> Self { .number(Double(value)) }
}

public struct OperationAction: Codable, Equatable, Sendable {
    public let command: [String]
    public init(_ command: [String]) { self.command = command }
}

public enum OperationReadPolicy {
    @TaskLocal public static var protectedDataRoot: URL?
    static func requireRecoveryPermission(paths: LauncherPaths, kind: String, instanceID: UUID) throws {
        if protectedDataRoot?.standardizedFileURL == paths.root.standardizedFileURL {
            throw OperationFailure("RECOVERY_REQUIRED", Messages.CLIInterface.tff19ae82a321.localized,
                nextActions: [.init(["recovery", "apply", kind, instanceID.uuidString, "--yes"])])
        }
    }
}

public struct OperationFailure: LocalizedError, Codable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let nextActions: [OperationAction]
    public let details: OperationValue
    public var errorDescription: String? { message }
    public init(_ code: String, _ message: String, retryable: Bool = false, nextActions: [OperationAction] = [], details: OperationValue = .null) {
        self.code = code; self.message = message; self.retryable = retryable; self.nextActions = nextActions; self.details = details
    }
}
