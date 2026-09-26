import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

public typealias Value = OperationValue

struct CommonOptions: ParsableArguments {
    @Flag(help: ArgumentHelp(Messages.CLIInterface.t0719f30a146c.localized)) var json = false
    @Option(help: ArgumentHelp(Messages.CLIInterface.t0232e54a0c07.localized)) var output: String = "text"
    @Option(help: ArgumentHelp(Messages.CLIInterface.tfeeb5f4ef393.localized)) var dataDir: String?
    @Option(help: ArgumentHelp(Messages.CLIInterface.t83e479a9529d.localized)) var language: String?
    @Flag(help: ArgumentHelp(Messages.CLIInterface.t1dfd9c76d588.localized)) var quiet = false
}

struct ParameterSpec: Codable, Sendable {
    let name: String
    let type: String
    let required: Bool
    let help: String
    var values: [String] = []
}

struct CommandSpec: Encodable, Sendable {
    let path: [String]
    let summary: String
    var operands: [ParameterSpec] = []
    var options: [ParameterSpec] = []
    var mutation = false
    var confirmation = false
    var userParticipation = false
    var examples: [String] = []
    var supportsDryRun: Bool { options.contains { $0.name == "dry-run" } }
    var configuration: CommandConfiguration { .init(commandName: path.last!, abstract: summary) }
    enum CodingKeys: String, CodingKey { case path, summary, operands, options, mutation, confirmation, userParticipation, examples, supportsDryRun, inputSchema, resultSchema, sideEffects }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path); try c.encode(summary, forKey: .summary)
        try c.encode(operands, forKey: .operands); try c.encode(options, forKey: .options)
        try c.encode(mutation, forKey: .mutation); try c.encode(confirmation, forKey: .confirmation)
        try c.encode(userParticipation, forKey: .userParticipation); try c.encode(examples, forKey: .examples)
        try c.encode(supportsDryRun, forKey: .supportsDryRun)
        try c.encode(CommandSchemas.input(self), forKey: .inputSchema)
        try c.encode(CommandSchemas.result(self), forKey: .resultSchema)
        try c.encode(CommandSchemas.sideEffects(self), forKey: .sideEffects)
    }
}

protocol ExecutableCommand: ParsableCommand {
    static var spec: CommandSpec { get }
    var common: CommonOptions { get }
    var operands: [String] { get }
    var parameters: [String: Value] { get }
}

extension ExecutableCommand {
    static var configuration: CommandConfiguration { spec.configuration }
    var request: CommandRequest { .init(spec: Self.spec, common: common, operands: operands, options: parameters) }
}

struct CommandRequest: Sendable {
    let spec: CommandSpec
    let common: CommonOptions
    let operands: [String]
    let options: [String: Value]
    var path: String { spec.path.joined(separator: " ") }
    var dryRun: Bool { flag("dry-run") }
    func flag(_ name: String) -> Bool { options[name]?.bool ?? false }
    func string(_ name: String) -> String? { options[name]?.string }
    func integer(_ name: String) -> Int? { options[name]?.int }
    func required(_ name: String) throws -> String {
        guard let value = string(name), !value.isEmpty else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tc3f4b95955b1(String(describing: name)).localized) }
        return value
    }
    func operand(_ index: Int = 0) throws -> String {
        guard operands.indices.contains(index) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t883e96f211e4(String(describing: spec.operands[safe: index]?.name ?? String(index + 1))).localized) }
        return operands[index]
    }
    func validate() throws {
        let minimum = spec.operands.filter(\.required).count
        guard operands.count >= minimum, operands.count <= spec.operands.count else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t8c27fffd692c(String(describing: spec.operands.map(\.name).joined(separator: " ")), String(describing: operands.count)).localized)
        }
        guard ["text", "json", "ndjson"].contains(common.output), !common.json || ["text", "json"].contains(common.output) else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.te36f73cbdb89.localized)
        }
        for option in spec.options {
            if option.required {
                let missing: Bool
                switch option.type {
                case "bool": missing = !flag(option.name)
                case "strings": missing = options[option.name] == nil || options[option.name] == .array([])
                default: missing = options[option.name] == nil || options[option.name] == .string("")
                }
                if missing { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tc3f4b95955b1(String(describing: option.name)).localized) }
            }
            if !option.values.isEmpty, let value = string(option.name), !option.values.contains(value) {
                throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.te66506826636(String(describing: option.name), String(describing: option.values.joined(separator: ", "))).localized)
            }
        }
        if let limit = integer("limit"), !(1...1000).contains(limit) { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t73e3848bbeee.localized) }
        if let offset = integer("offset"), offset < 0 { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.td3901a3793d1.localized) }
        if spec.confirmation && !dryRun && !flag("yes") {
            throw OperationFailure("CONFIRMATION_REQUIRED", Messages.CLIInterface.tf2d2570879da.localized)
        }
    }
    func page(_ values: [Value]) -> Value {
        let offset = integer("offset") ?? 0, limit = integer("limit") ?? 50
        let items = flag("all") ? values : Array(values.dropFirst(offset).prefix(limit))
        return .object(["items": .array(items), "total": .integer(values.count), "offset": .integer(flag("all") ? 0 : offset), "hasMore": .bool(!flag("all") && offset + items.count < values.count)])
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// ArgumentParser's option wrappers contain only value types here. Requests stay
// on MainActor; these declarations also allow immutable options in progress work.
extension CommonOptions: @unchecked Sendable {}
