import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageWorld(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, paths, _) = try await context(request), id = try uuid(request.operand())
        _ = try InstanceService(paths: paths).resolve(id: id)
        let manager = WorldManager(paths: paths, instanceID: id), action = request.spec.path.dropFirst().joined(separator: " ")
        if action == "list" { return request.page(try await manager.worlds().map(worldValue)) }
        if action == Messages.CLIInterface.te2cdbe92a0c7.localized { return request.page(try await manager.backups().map(backupValue)) }
        if action == "import" {
            let file = URL(fileURLWithPath: try request.operand(1))
            guard FileManager.default.fileExists(atPath: file.path) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t68a342df34e2.localized) }
            if request.dryRun { return .object(["dryRun": .bool(true), "file": .string(file.path)]) }
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            let folder = try await manager.importWorld(from: file) { output.event("progress", .object(["completed": .integer($0), "total": .integer($1)])) }
            return .object(["folder": .string(folder)])
        }
        if action == Messages.CLIInterface.t1b8effc90c68.localized || action == Messages.CLIInterface.t741c3180946d.localized {
            let name = try request.operand(1)
            guard let backup = try await manager.backups().first(where: { $0.id == name }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t813a5dd4816c.localized) }
            if request.dryRun { return .object(["dryRun": .bool(true), "backup": backupValue(backup), "replace": .bool(request.flag("replace"))]) }
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            if action == Messages.CLIInterface.t741c3180946d.localized { try await manager.removeBackup(backup); return .object(["removed": .string(backup.id)]) }
            let folder = try await manager.restore(backup, replaceExisting: request.flag("replace")) { output.event("progress", .object(["completed": .integer($0), "total": .integer($1)])) }
            return .object(["folder": .string(folder)])
        }
        let folder = try request.operand(1)
        guard let world = try await manager.worlds().first(where: { $0.folder == folder }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t90c2d3c97aae.localized) }
        if action == "show" { return worldValue(world) }
        let file = action == "export" ? try URL(fileURLWithPath: request.operand(2)) : nil
        if let file { try requireNewFile(file) }
        if request.dryRun { return .object(["dryRun": .bool(true), "world": worldValue(world), "file": .text(file?.path)]) }
        let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
        switch action {
        case "remove": try await manager.removeWorld(folder: folder)
        case "export": try await manager.exportWorld(folder: folder, to: file!) { output.event("progress", .object(["completed": .integer($0), "total": .integer($1)])) }
        case Messages.CLIInterface.t8ee474107a6f.localized: return backupValue(try await manager.backup(folder: folder, reason: request.string("reason")) { output.event("progress", .object(["completed": .integer($0), "total": .integer($1)])) })
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.ta7cd75ee2906.localized)
        }
        return .object(["folder": .string(folder), "action": .string(action), "file": .text(file?.path)])
    }
    @MainActor static func manageDataPack(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, paths, downloader) = try await context(request), id = try uuid(request.operand())
        let instance = try InstanceService(paths: paths).resolve(id: id), manager = WorldManager(paths: paths, instanceID: id)
        let action = request.spec.path.dropFirst().joined(separator: " "), target = try request.operand(1)
        let downloads = WorldDataPackDownloads()
        if action == "search" {
            let page = try await downloads.search(target, game: instance.gameVersion)
            var result = request.page(page.hits.map { projectValue(.modrinth($0)) }).object!
            result["providerTotal"] = .integer(page.total_hits); return .object(result)
        }
        if action == "versions" { return request.page(try await downloads.versions(project: target, game: instance.gameVersion).map { versionValue(.modrinth($0)) }) }
        if action == "list" {
            return request.page(try await manager.dataPacks(folder: target).map { .object(["id": .string($0.id), "enabled": .bool($0.enabled), "description": .string($0.description), "error": .text($0.error)]) })
        }
        if action == Messages.CLIInterface.tee60e235e97a.localized || action == Messages.CLIInterface.tcc3d1a4da37b.localized {
            let priority = try await manager.dataPackPriority(folder: target)
            let keys = action == Messages.CLIInterface.tcc3d1a4da37b.localized ? strings(request, "key") : priority.keys
            if action == Messages.CLIInterface.tcc3d1a4da37b.localized {
                guard keys.count == priority.keys.count, Set(keys) == Set(priority.keys), Set(keys).count == keys.count else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tcaf18c90c73d.localized) }
                if !request.dryRun {
                    let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
                    try await manager.setDataPackPriority(keys, folder: target, expecting: priority)
                }
            }
            return .object(["keys": .array(keys.map(Value.string)), "dryRun": .bool(request.dryRun)])
        }
        if action == "install" {
            let versions = try await downloads.versions(project: request.operand(2), game: instance.gameVersion)
            guard let version = versions.first(where: { version in request.string("version").map { $0 == version.id } ?? (version.version_type == nil || version.version_type == "release") }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.tdd5661a06a84.localized) }
            let plan = try await downloads.prepare(version, game: instance.gameVersion)
            if !request.dryRun {
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
                try await downloads.install(plan, instance: instance, folder: target, paths: paths, downloader: downloader, progress: { output.progress($0) })
            }
            return .object(["dryRun": .bool(request.dryRun), "versions": .array(plan.versions.map { versionValue(.modrinth($0)) }), "downloadBytes": .integer(plan.downloadSize)])
        }
        let name = try request.operand(2)
        if action != "import" {
            guard try await manager.dataPacks(folder: target).contains(where: { $0.id == name }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t921d4db04b98.localized) }
        } else if !FileManager.default.fileExists(atPath: name) { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t68a342df34e2.localized) }
        if !request.dryRun {
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            switch action {
            case "import": try await manager.importDataPack(from: URL(fileURLWithPath: name), folder: target)
            case "enable", "disable": try await manager.setDataPackEnabled(action == "enable", name: name, folder: target)
            case "remove": _ = try await manager.removeDataPack(name: name, folder: target)
            default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t31dc407e9871.localized)
            }
        }
        return .object(["dryRun": .bool(request.dryRun), "world": .string(target), "name": .string(name), "effectiveOnNextWorldLoad": .bool(true)])
    }
    @MainActor static func manageSchematic(_ request: CommandRequest) async throws -> Value {
        let (_, paths, _) = try await context(request), id = try uuid(request.operand())
        _ = try InstanceService(paths: paths).resolve(id: id)
        let manager = SchematicManager(paths: paths, instanceID: id), action = request.spec.path.last!, directory = request.string("directory") ?? ""
        if action == "list" { return request.page(try await manager.list(directory: directory).map(schematicValue)) }
        let target = try request.operand(1)
        if action == "import" || action == "mkdir" {
            if action == "import", !FileManager.default.fileExists(atPath: target) { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t68a342df34e2.localized) }
            _ = try await manager.list(directory: directory)
            if !request.dryRun {
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
                if action == "import" { try await manager.importFiles([URL(fileURLWithPath: target)], directory: directory) }
                else { try await manager.createFolder(target, directory: directory) }
            }
            return .object(["dryRun": .bool(request.dryRun), "target": .string(target), "directory": .string(directory)])
        }
        let parent = target.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")
        guard let entry = try await manager.list(directory: parent).first(where: { $0.id == target }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t90e3b5019ad0.localized) }
        if action == "info" {
            let info = try await manager.info(entry)
            return .object(["entry": schematicValue(entry), "name": .text(info.name), "author": .text(info.author), "description": .text(info.description),
                "dimensions": .array(info.dimensions.map(Value.integer)), "blocks": info.blocks.map(Value.integer) ?? .null, "regions": info.regions.map(Value.integer) ?? .null,
                "formatVersion": info.formatVersion.map(Value.integer) ?? .null, "gameDataVersion": info.gameDataVersion.map(Value.integer) ?? .null])
        }
        let file = action == "export" ? try URL(fileURLWithPath: request.operand(2)) : nil
        if let file { try requireNewFile(file) }
        if !request.dryRun {
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            if let file { try await manager.export(entry, to: file) } else { _ = try await manager.remove(entry) }
        }
        return .object(["dryRun": .bool(request.dryRun), "entry": schematicValue(entry), "file": .text(file?.path)])
    }
    static func worldValue(_ world: WorldSnapshot) -> Value {
        .object(["folder": .string(world.folder), "name": .string(world.name), "version": .text(world.version), "gameType": world.gameType.map(Value.integer) ?? .null,
            "hardcore": .bool(world.hardcore), "bytes": world.size.map(Value.integer) ?? .null, "lastPlayed": .text(world.lastPlayed?.ISO8601Format()), "error": .text(world.metadataError)])
    }
    static func backupValue(_ backup: WorldBackup) -> Value {
        .object(["id": .string(backup.id), "world": .text(backup.metadata?.worldFolder), "worldName": .text(backup.metadata?.worldName), "createdAt": .string(backup.createdAt.ISO8601Format()), "bytes": .integer(backup.size)])
    }
    static func schematicValue(_ entry: SchematicEntry) -> Value {
        .object(["path": .string(entry.id), "directory": .bool(entry.isDirectory), "bytes": .integer(entry.size), "modifiedAt": .text(entry.modifiedAt?.ISO8601Format())])
    }
}
