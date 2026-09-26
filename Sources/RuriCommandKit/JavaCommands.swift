import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageJava(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, paths, downloader) = try await context(request), action = request.spec.path.last!
        let installer = JavaInstaller(paths: paths)
        if action == "list" {
            return request.page(await JavaDiscovery.inventory(paths: paths).map { entry in
                .object(["path": .string(entry.path), "managedID": .text(entry.managedID), "source": .string(entry.managedID != nil ? "managed" : entry.manual ? "manual" : entry.configured ? "configuration" : "discovery"),
                    "runtime": entry.runtime.map(javaValue) ?? .null, "issue": .text(entry.issue)])
            })
        }
        if action == "available" {
            let available = try await installer.available().filter { (request.integer("major") == nil || $0.major == request.integer("major")) && (request.string("architecture") == nil || $0.architecture == request.string("architecture")) }
            return request.page(available.map(remoteJavaValue))
        }
        let target = try request.operand()
        switch action {
        case "add":
            let runtime = try await Task.detached { try JavaDiscovery.inspect(JavaDiscovery.executable(in: URL(fileURLWithPath: target)).path) }.value
            if !request.dryRun { _ = try await JavaRuntimeStore.add(URL(fileURLWithPath: target), paths: paths) }
            return .object(["dryRun": .bool(request.dryRun), "runtime": javaValue(runtime)])
        case "forget":
            if !request.dryRun { _ = try JavaRuntimeStore.forget(target, paths: paths) }
            return .object(["dryRun": .bool(request.dryRun), "path": .string(target)])
        case "default":
            let selection: Value
            if target == "automatic" { selection = .object(["mode": .string("automatic"), "major": .null, "path": .null]) }
            else {
                let java = try JavaDiscovery.executable(in: URL(fileURLWithPath: target))
                _ = try await Task.detached { try JavaDiscovery.inspect(java.path) }.value
                selection = .object(["mode": .string("path"), "path": .string(java.path), "major": .null])
            }
            return try ConfigurationService(paths: paths).apply(.init(set: ["java": selection]), scope: "defaults", dryRun: request.dryRun)
        case "references", "remove":
            let refs = try JavaRuntimeStore.references(to: target, paths: paths, partial: request.flag("partial"))
            if action == "references" { return request.page(refs.map(Value.string)) }
            if request.dryRun { return .object(["dryRun": .bool(true), "id": .string(target), "references": .array(refs.map(Value.string))]) }
            let result = try JavaRuntimeStore.trash(target, paths: paths, resetReferences: request.flag("reset-references"), partial: request.flag("partial"))
            return .object(["id": .string(target), "trashedPath": .text(result.trashedURL?.path)])
        case "install", "repair":
            var remote = action == "repair" ? JavaRuntimeStore.descriptor(target, paths: paths) : nil
            if remote == nil { remote = try await installer.available().first { $0.id == target } }
            guard let remote else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t33604425d94f.localized, nextActions: [.init(["java", "available", "--json"])]) }
            if request.dryRun { return .object(["dryRun": .bool(true), "runtime": remoteJavaValue(remote)]) }
            return javaValue(try await installer.install(remote, downloader: downloader, repairing: action == "repair", progress: { output.progress($0) }))
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tab6287c24a41.localized)
        }
    }
    static func javaValue(_ java: JavaRuntime) -> Value {
        .object(["path": .string(java.path), "major": .integer(java.major), "version": .string(java.version), "architecture": .string(java.architecture), "vendor": .string(java.vendor)])
    }
    static func remoteJavaValue(_ java: RemoteJava) -> Value {
        .object(["id": .string(java.id), "major": .integer(java.major), "version": .string(java.version), "architecture": .string(java.architecture)])
    }
}
