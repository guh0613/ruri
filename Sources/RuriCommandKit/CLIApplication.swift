import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

public enum CLIApplication {
    @MainActor public static func run(_ arguments: [String], write: @escaping @Sendable (Data, Bool) -> Void = { data, error in
        try? (error ? FileHandle.standardError : FileHandle.standardOutput).write(contentsOf: data)
    }) async -> Int32 {
        let args = normalizeGlobals(arguments)
        var output = CommandOutput(format: requestedFormat(args), quiet: args.contains("--quiet"), write: write)
        var activeRequest: CommandRequest?
        do {
            let command: any ExecutableCommand
            do {
                var parsed = try RuriCommand.parseAsRoot(args)
                if let executable = parsed as? any ExecutableCommand { command = executable }
                else {
                    // ArgumentParser returns a built-in help command carrying
                    // the requested command stack. Running it produces the
                    // correct help request, including the root command name.
                    try parsed.run()
                    return 0
                }
            }
            catch {
                let code = RuriCommand.exitCode(for: error).rawValue
                if code == 0 { output.help(RuriCommand.message(for: error)); return 0 }
                throw OperationFailure("INVALID_ARGUMENT", RuriCommand.message(for: error))
            }
            let request = command.request
            try request.validate()
            activeRequest = request
            output = CommandOutput(format: request.common.json ? .json : .init(rawValue: request.common.output)!, quiet: request.common.quiet, write: write)
            let context = request.common.language.map { LocalizationContext(language: $0) } ?? .processDefault
            let result = try await LocalizationContext.$current.withValue(context) {
                try await OperationReadPolicy.$protectedDataRoot.withValue(request.dryRun || !request.spec.mutation ? basePaths(request).root : nil) {
                    try await execute(request, output: output)
                }
            }
            var payload = result
            if request.spec.mutation, var fields = result.object {
                fields["dryRun"] = .bool(request.dryRun); payload = .object(fields)
            }
            let warnings = (try? result["warnings"].decode([String].self)) ?? []
            output.result(payload, warnings: warnings); return 0
        } catch {
            var failure: OperationFailure
            if error is CancellationError || Task.isCancelled || (error as? InstanceMoveFailure)?.cancelled == true || (error as? RunDirectoryCopyFailure)?.cancelled == true {
                let original = error as? OperationFailure
                failure = .init("CANCELLED", Messages.CLIInterface.t386cf3b4f8ac.localized, nextActions: original?.nextActions ?? [], details: original?.details ?? .null)
            }
            else if let value = error as? OperationFailure { failure = value }
            else if let value = error as? RuriError {
                if case .httpResponse(let status, let host) = value {
                    failure = .init("NETWORK_ERROR", value.localizedDescription, retryable: status == 429 || status >= 500, details: .object(["httpStatus": .integer(status), "host": .string(host)]))
                } else { failure = .init("SERVICE_ERROR", value.localizedDescription, details: .object(["messageID": .text(value.messageID)])) }
            } else if let value = error as? URLError {
                failure = .init("NETWORK_ERROR", value.localizedDescription, retryable: true)
            } else { failure = .init("IO_ERROR", error.localizedDescription) }
            if let request = activeRequest { failure = await addingRecovery(to: failure, underlying: error, request: request, output: output) }
            output.result(error: failure)
            return failure.code == "INVALID_ARGUMENT" ? 2 : failure.code == "CANCELLED" ? 130 : 1
        }
    }

    @MainActor static func execute(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        if request.spec.path.first == "config" { return try configure(request) }
        if request.spec.path.first == "doctor" { return try await doctor(request) }
        if request.spec.path.first == "recovery" { return try await manageRecovery(request, output: output) }
        if request.spec.path == ["instance", "import"] || request.spec.path.first == "pack" { return try await managePack(request, output: output) }
        if request.spec.path.first == "download" { return try await fetch(request, output: output) }
        if request.spec.path.first == "instance" { return try await manageInstance(request, output: output) }
        if request.spec.path.first == "directory" { return try await manageDirectory(request, output: output) }
        if request.spec.path.first == "java" { return try await manageJava(request, output: output) }
        if request.spec.path.first == "account" { return try await manageAccount(request, output: output) }
        if request.spec.path.first == "launch" { return try await manageLaunch(request, output: output) }
        if request.spec.path.first == "session" { return try await manageSession(request, output: output) }
        if request.spec.path.first == "catalog" { return try await manageCatalog(request) }
        if request.spec.path.first == "content" { return try await manageContent(request, output: output) }
        if request.spec.path.first == "world" { return try await manageWorld(request, output: output) }
        if request.spec.path.first == "datapack" { return try await manageDataPack(request, output: output) }
        if request.spec.path.first == "schematic" { return try await manageSchematic(request) }
        switch request.path {
        case "schema":
            let matching = CommandRegistry.commands.filter { Array($0.path.prefix(request.operands.count)) == request.operands }
            guard !matching.isEmpty else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t066f88703d3a.localized) }
            return .object(["commands": try .encode(matching), "output": .object(["schemaVersion": .integer(1), "formats": .array(["text", "json", "ndjson"].map(Value.string)),
                "result": .array(["schemaVersion", "ok", "data", "warnings", "error"].map(Value.string)),
                "error": .array(["code", "message", "retryable", "nextActions", "details"].map(Value.string))]),
                "globalOptions": .array(["--json", "--output", "--data-dir", "--language", "--quiet"].map(Value.string)),
                "configuration": try ConfigurationService.schema(), "patchSchemas": CommandSchemas.patches])
        case "app info":
            return .object(["version": .string(BuildConfiguration().version), "schemaVersion": .integer(1), "application": .text(RuriInstallation.application()?.path),
                "cli": .text(RuriInstallation.cliExecutable?.path), "dataDirectory": .string(basePaths(request).root.path)])
        case "app language get", "app language set":
            let preferences = UserDefaults(suiteName: "dev.ruri.launcher")!
            if request.path.hasSuffix("set") {
                let language = try request.operand()
                guard language == "system" || LocalizationContext.supportedLanguages.contains(language) else {
                    throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t55d7eb65faaa.localized, details: .array((["system"] + LocalizationContext.supportedLanguages).map(Value.string)))
                }
                if !request.dryRun { preferences.set(language, forKey: LocalizationContext.preferenceKey) }
                return .object(["language": .string(language), "restartRequired": .bool(true), "dryRun": .bool(request.dryRun)])
            }
            return .object(["language": .string(preferences.string(forKey: LocalizationContext.preferenceKey) ?? "system"), "supported": .array(LocalizationContext.supportedLanguages.map(Value.string))])
        case "cli status", "cli install", "cli uninstall":
            let service = try CLIInstallation(binDirectory: request.string("bin-dir").map { URL(fileURLWithPath: $0) })
            if request.path == "cli install" { return try service.install(dryRun: request.dryRun) }
            if request.path == "cli uninstall" { return try service.uninstall(dryRun: request.dryRun) }
            return service.status()
        default: throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t616e37d3d71a.localized)
        }
    }
    static func basePaths(_ request: CommandRequest) -> LauncherPaths {
        LauncherPaths(root: (request.common.dataDir ?? ProcessInfo.processInfo.environment["RURI_DATA_DIR"]).map { URL(fileURLWithPath: $0) })
    }
    private static func requestedFormat(_ args: [String]) -> CommandOutput.Format {
        let options = Array(args.prefix { $0 != "--" })
        if options.contains("--json") { return .json }
        if let item = options.first(where: { $0.hasPrefix("--output=") }), let format = CommandOutput.Format(rawValue: String(item.dropFirst(9))) { return format }
        if let index = options.firstIndex(of: "--output"), let name = options[safe: index + 1], let format = CommandOutput.Format(rawValue: name) { return format }
        return .text
    }
    /// Leading global options, including help, move to the leaf command.
    /// Options after `--` remain literal operands.
    static func normalizeGlobals(_ args: [String]) -> [String] {
        var prefix: [String] = [], remaining = args
        while let first = remaining.first {
            let name = first.split(separator: "=", maxSplits: 1).first.map(String.init) ?? first
            if ["--json", "--quiet", "--help", "-h", "--help-hidden"].contains(name) { prefix.append(remaining.removeFirst()) }
            else if ["--output", "--data-dir", "--language"].contains(name) {
                prefix.append(remaining.removeFirst())
                if !first.contains("="), let next = remaining.first, !next.hasPrefix("--") { prefix.append(remaining.removeFirst()) }
            } else { break }
        }
        if let index = remaining.firstIndex(of: "--") { remaining.insert(contentsOf: prefix, at: index) }
        else { remaining.append(contentsOf: prefix) }
        return remaining
    }
}
