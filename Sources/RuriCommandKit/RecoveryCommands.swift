import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageRecovery(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (state, paths, _) = try await context(request)
        if request.spec.path.last == "list" {
            let filter = try request.string("instance").map(uuid)
            if let filter { _ = try InstanceService(paths: paths).resolve(id: filter) }
            var items: [Value] = [], issues: [Value] = []
            func entry(_ kind: String, target: UUID, transaction: UUID? = nil, extra: [String: Value] = [:]) -> Value {
                .object(extra.merging(["kind": .string(kind), "target": .string(target.uuidString), "transaction": .text(transaction?.uuidString),
                    "nextAction": .array((["recovery", "apply", kind, target.uuidString] + (transaction.map { ["--transaction", $0.uuidString] } ?? [])).map(Value.string))]) { _, new in new })
            }
            for instance in state.instances where filter == nil || instance.id == filter {
                do {
                    if let pending = try await InstanceCopier(paths: paths).pending(instanceID: instance.id) {
                        items.append(entry("instance-copy", target: instance.id, transaction: pending.owner.transactionID, extra: ["committed": .bool(pending.committed), "workspace": .string(pending.workspace.path)]))
                    }
                    if let pending = try await InstanceMover(paths: paths).pending(instanceID: instance.id) {
                        items.append(entry("instance-move", target: instance.id, transaction: pending.id, extra: ["committed": .bool(pending.committed), "workspace": .string(pending.workspace.path)]))
                    }
                    if let pending = try await GameRunDirectoryChange(paths: paths).pendingCopy(instanceID: instance.id) {
                        items.append(entry("run-directory", target: instance.id, transaction: pending.owner.transactionID, extra: ["committed": .bool(pending.committed)]))
                    }
                    if ModpackUpdateStore.hasPending(paths: paths, instanceID: instance.id) { items.append(entry("pack-update", target: instance.id)) }
                    for (kind, folder) in [("content", "content-transaction"), ("world", "world-restore")] {
                        if FileManager.default.fileExists(atPath: paths.gameDataState(instance.id).appendingPathComponent(folder).path) { items.append(entry(kind, target: instance.id)) }
                    }
                    for record in try GameSessionStore.list(paths: paths, instanceID: instance.id) where !record.state.isFinished && GameMonitorClient.activity(record) != .monitoring {
                        let status = GameSessionRecovery.status(record)
                        items.append(entry("session", target: instance.id, transaction: record.id, extra: ["status": .string(String(describing: status)), "explanation": .string(status.explanation)]))
                    }
                } catch { issues.append(.object(["instanceID": .string(instance.id.uuidString), "error": .string(error.localizedDescription)])) }
            }
            if filter == nil {
                for directory in state.gameDirectories ?? [] where directory.isMinecraft {
                    do {
                        for pending in try RepositoryImportStore.pending(directoryID: directory.id, paths: paths) {
                            items.append(entry("repository-import", target: directory.id, transaction: pending.id, extra: ["name": .string(pending.name), "canFinish": .bool(pending.canFinish)]))
                        }
                    } catch { issues.append(.object(["directoryID": .string(directory.id.uuidString), "error": .string(error.localizedDescription)])) }
                }
            }
            var result = request.page(items).object!; result["issues"] = .array(issues); return .object(result)
        }
        let kind = try request.operand(), id = try uuid(request.operand(1)), transaction = try request.string("transaction").map(uuid)
        guard ["instance-copy", "instance-move", "run-directory", "pack-update", "repository-import", "session", "content", "world"].contains(kind) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t1e2f741698a1.localized) }
        if ["instance-copy", "instance-move", "run-directory", "repository-import", "session"].contains(kind), transaction == nil { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t7f8c861b7d62.localized) }
        if kind == "repository-import" { _ = try request.required("mode") }
        if request.dryRun { return .object(["dryRun": .bool(true), "kind": .string(kind), "target": .string(id.uuidString), "transaction": .text(transaction?.uuidString)]) }
        var result: [String: Value] = ["kind": .string(kind), "target": .string(id.uuidString)]
        switch kind {
        case "instance-copy":
            let recovered = try await InstanceCopier(paths: paths).recover(sourceID: id, transactionID: transaction!)
            result["warning"] = .text(recovered.warning); result["preservedCopy"] = .text(recovered.preservedCopy?.path)
        case "instance-move":
            let recovered = try await InstanceMover(paths: paths).recover(instanceID: id, transactionID: transaction!, preservingSource: request.flag("keep-source")) { output.event("progress", .object(["phase": .string($0.phase.rawValue), "bytesCopied": .integer($0.bytesCopied)])) }
            result["warning"] = .text(recovered.warning); result["preservedFiles"] = .array(recovered.preservedFiles.map { .string($0.path) })
        case "run-directory":
            let recovered = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: id, transactionID: transaction!)
            result["warning"] = .text(recovered.warning); result["preservedCopy"] = .text(recovered.preservedCopy?.path)
        case "pack-update": _ = try ModpackUpdateStore.recover(instanceID: id, paths: paths)
        case "repository-import":
            let preserved = try RepositoryImportStore.recover(transaction!, directoryID: id, finish: request.string("mode") == "finish", paths: paths)
            result["preservedFiles"] = .text(preserved?.path)
        case "session":
            let record = try GameSessionStore.load(paths: paths, instanceID: id, sessionID: transaction!)
            return sessionValue(try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: request.flag("confirm-game-ended")))
        default:
            _ = try InstanceService(paths: paths).resolve(id: id)
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            if kind == "content" { try await ContentManager(paths: paths, instanceID: id).recover() }
            else { try await WorldManager(paths: paths, instanceID: id).recover() }
        }
        return .object(result)
    }
    @MainActor static func doctor(_ request: CommandRequest) async throws -> Value {
        let base = basePaths(request)
        var checks: [Value] = []
        func check(_ name: String, _ ok: Bool, _ details: Value = .null) { checks.append(.object(["check": .string(name), "ok": .bool(ok), "details": details])) }
        let state: PersistentState
        do { state = try StateStore.load(base); check("state", true) }
        catch { throw OperationFailure("STATE_INVALID", error.localizedDescription, details: .object(["path": .string(base.state.path)])) }
        let paths = base.configured(with: state)
        for directory in state.gameDirectories ?? [] { check("directory", (try? directory.validateAvailability()) != nil, directoryValue(directory, detached: false)) }
        check("monitor", (try? GameMonitorClient.helperExecutable()) != nil)
        if let app = RuriInstallation.application() { check("gameHost", FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/Helpers/RuriGame.app/Contents/MacOS/ruri-game").path)) }
        for account in state.accounts {
            let availability = CredentialStore.availability(for: account.id, kind: account.kind)
            check("credentials", ["available", "notRequired"].contains(availability), .object(["accountID": .string(account.id.uuidString), "availability": .string(availability)]))
        }
        let id = try request.string("instance").map(uuid)
        if let id { _ = try InstanceService(paths: paths).resolve(id: id) }
        let runtimes = await JavaDiscovery.scan(paths: paths, extra: state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path })
        for stored in state.instances where id == nil || stored.id == id {
            do {
                try paths.validateBinding(stored)
                let instance = try stored.launchSnapshot(defaults: state.settings, workload: MemoryWorkload.scan(paths: paths, instance: stored))
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let java = try GameJavaRequirement(instance: instance, manifest: manifest).require(from: runtimes)
                check("instance", true, .object(["id": .string(stored.id.uuidString), "java": javaValue(java)]))
            } catch { check("instance", false, .object(["id": .string(stored.id.uuidString), "message": .string(error.localizedDescription)])) }
        }
        let healthy = checks.allSatisfy { $0["ok"].bool == true }, report: Value = .object(["healthy": .bool(healthy), "checks": .array(checks)])
        guard healthy else { throw OperationFailure("CHECKS_FAILED", Messages.CLIInterface.tf19d497be38f.localized, details: report) }
        return report
    }
}

extension CLIApplication {
    /// Failure discovery is read-only, and must never replace the original
    /// error when a damaged journal or unavailable directory cannot be read.
    @MainActor static func addingRecovery(to failure: OperationFailure, underlying: any Error, request: CommandRequest, output: CommandOutput) async -> OperationFailure {
        guard request.spec.mutation, ["instance", "directory", "pack", "content", "world", "datapack", "launch", "recovery"].contains(request.spec.path.first ?? ""),
              !["INVALID_ARGUMENT", "CONFIRMATION_REQUIRED", "NOT_FOUND"].contains(failure.code) else { return failure }
        let instanceID = request.operands.first.flatMap(UUID.init(uuidString:)) ?? failure.details["instanceID"].string.flatMap(UUID.init(uuidString:))
        var options: [String: Value] = ["all": .bool(true)]
        if let instanceID { options["instance"] = .string(instanceID.uuidString) }
        let query = CommandRequest(spec: RecoveryListCommand.spec, common: request.common, operands: [], options: options)
        let snapshot = try? await OperationReadPolicy.$protectedDataRoot.withValue(basePaths(request).root) { try await manageRecovery(query, output: output) }
        var items = (try? snapshot?["items"].decode([Value].self)) ?? []
        if instanceID == nil, let directory = request.string("directory").flatMap({ try? directoryID($0) }) {
            items = items.filter { $0["target"].string == directory.uuidString }
        }
        var preserved: [String] = []
        if let error = underlying as? InstanceMoveFailure { preserved = error.preservedFiles.map(\.path) }
        if let error = underlying as? RunDirectoryCopyFailure, let path = error.preservedCopy?.path { preserved = [path] }
        if let error = underlying as? RepositoryImportFailure, let path = error.preservedFiles?.path { preserved = [path] }
        guard !items.isEmpty || !preserved.isEmpty || failure.code == "CANCELLED" else { return failure }
        var details = failure.details.object ?? (failure.details == .null ? [:] : ["cause": failure.details])
        details["recovery"] = .array(items)
        if !preserved.isEmpty { details["preservedFiles"] = .array(preserved.map(Value.string)) }
        var actions = failure.nextActions
        for item in items {
            if let command = try? item["nextAction"].decode([String].self) { actions.append(.init(command)) }
        }
        if actions.isEmpty { actions = [.init(["recovery", "list"] + (instanceID.map { ["--instance", $0.uuidString] } ?? []) + ["--json"])] }
        return .init(failure.code, failure.message, retryable: failure.retryable, nextActions: actions, details: .object(details))
    }
}
