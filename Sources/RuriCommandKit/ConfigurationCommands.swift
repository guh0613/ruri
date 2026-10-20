import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    static func configure(_ request: CommandRequest) throws -> Value {
        if request.spec.path.last == "fields" { return try configurationFields(request) }
        let service = ConfigurationService(paths: basePaths(request)), scope = try request.required("scope")
        if request.spec.path.last == "get" {
            let report = try service.read(scope: scope, showSecrets: request.flag("show-secrets"))
            if let key = request.operands.first {
                let fields = scope == "app" ? ConfigurationService.appFields : ConfigurationService.launchFields
                guard fields.contains(where: { $0.name == key || $0.name.hasPrefix(key + ".") }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.unknownConfigField.localized) }
                return .object(["scope": .string(scope), "key": .string(key), "revision": report["revision"], "explicit": ConfigurationService.get(report["explicit"], key),
                    "effective": ConfigurationService.get(report["effective"], key), "source": report["sources"][String(key.split(separator: ".")[0])]])
            }
            return report
        }
        let patch: ConfigurationPatch
        switch request.spec.path.last {
        case "set":
            let raw = try request.operand(1)
            guard let value = try? JSONDecoder().decode(Value.self, from: Data(raw.utf8)) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.configValueMustBeJson.localized) }
            patch = .init(set: [try request.operand(): value])
        case "reset": patch = .init(reset: [try request.operand()])
        case "inherit": patch = .init(inherit: [try request.operand()])
        default:
            do { patch = try JSONDecoder().decode(ConfigurationPatch.self, from: readInput(try request.required("file"))) }
            catch let failure as OperationFailure { throw failure }
            catch { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.invalidConfigPatchJson.localized) }
        }
        let revision = try request.string("if-revision").map { try uuid($0) }
        return try service.apply(patch, scope: scope, expectedRevision: revision, dryRun: request.dryRun)
    }
    /// Field descriptions only; no state or instance configuration is read.
    static func configurationFields(_ request: CommandRequest) throws -> Value {
        let scope = request.string("scope"), prefix = request.operands.first ?? ""
        var fields: [Value] = []
        for (scopes, items) in [(["app"], ConfigurationService.appFields), (["defaults", "instance"], ConfigurationService.launchFields)] where scope.map(scopes.contains) ?? true {
            for field in items where field.name.hasPrefix(prefix) {
                var value = try Value.encode(field).object ?? [:]
                value["scopes"] = .array(scopes.map(Value.string))
                value["unit"] = .text(configurationUnit(field.name))
                if scopes.contains("instance") { value["group"] = .string(String(field.name.split(separator: ".")[0])) }
                fields.append(.object(value))
            }
        }
        guard !fields.isEmpty || prefix.isEmpty else {
            let names = (ConfigurationService.appFields + ConfigurationService.launchFields).map(\.name)
            throw CommandLineInvocation.failure(Messages.CLIInterface.unknownConfigField.localized, suggestion: CommandLineInvocation.suggestion(for: prefix, in: names + ConfigurationService.groups), path: request.spec.path)
        }
        return .object(["scope": .text(scope), "prefix": prefix.isEmpty ? .null : .string(prefix), "fields": .array(fields)])
    }
    /// Units implied by field names. Values are never converted.
    static func configurationUnit(_ name: String) -> String? {
        if name.hasSuffix("MB") { return "MB" }
        if name.hasSuffix("Seconds") { return "seconds" }
        if name == "window.width" || name == "window.height" { return "pixels" }
        return nil
    }
    static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.validUuidRequired.localized) }; return id
    }
    static func readInput(_ file: String, maximumBytes: Int = 1_048_576) throws -> Data {
        let handle = try file == "-" ? FileHandle.standardInput : FileHandle(forReadingFrom: URL(fileURLWithPath: file))
        defer { if file != "-" { try? handle.close() } }
        var data = Data()
        while data.count <= maximumBytes, let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.inputSizeLimitExceeded.localized) }; return data
    }
}
