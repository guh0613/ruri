import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    static func configure(_ request: CommandRequest) throws -> Value {
        let service = ConfigurationService(paths: basePaths(request)), scope = try request.required("scope")
        if request.spec.path.last == "get" {
            let report = try service.read(scope: scope, showSecrets: request.flag("show-secrets"))
            if let key = request.operands.first {
                let fields = scope == "app" ? ConfigurationService.appFields : ConfigurationService.launchFields
                guard fields.contains(where: { $0.name == key || $0.name.hasPrefix(key + ".") }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tdf61274dcc9c.localized) }
                return .object(["scope": .string(scope), "key": .string(key), "revision": report["revision"], "explicit": ConfigurationService.get(report["explicit"], key),
                    "effective": ConfigurationService.get(report["effective"], key), "source": report["sources"][String(key.split(separator: ".")[0])]])
            }
            return report
        }
        let patch: ConfigurationPatch
        switch request.spec.path.last {
        case "set":
            let raw = try request.operand(1)
            guard let value = try? JSONDecoder().decode(Value.self, from: Data(raw.utf8)) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.te3e619f346d3.localized) }
            patch = .init(set: [try request.operand(): value])
        case "reset": patch = .init(reset: [try request.operand()])
        case "inherit": patch = .init(inherit: [try request.operand()])
        default:
            do { patch = try JSONDecoder().decode(ConfigurationPatch.self, from: readInput(try request.required("file"))) }
            catch let failure as OperationFailure { throw failure }
            catch { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t64229bd16ecc.localized) }
        }
        let revision = try request.string("if-revision").map { try uuid($0) }
        return try service.apply(patch, scope: scope, expectedRevision: revision, dryRun: request.dryRun)
    }
    static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t332cdb6a53b4.localized) }; return id
    }
    static func readInput(_ file: String, maximumBytes: Int = 1_048_576) throws -> Data {
        let handle = try file == "-" ? FileHandle.standardInput : FileHandle(forReadingFrom: URL(fileURLWithPath: file))
        defer { if file != "-" { try? handle.close() } }
        var data = Data()
        while data.count <= maximumBytes, let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tf7eb23752b1e.localized) }; return data
    }
}
