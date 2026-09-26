import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageInstance(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (state, paths, downloader) = try await context(request)
        let service = InstanceService(paths: paths), action = request.spec.path.dropFirst().joined(separator: " ")
        switch action {
        case "list":
            var items = state.instances
            if let name = request.string("name") { items = items.filter { $0.name == name } }
            if let directory = request.string("directory") { let id = try directoryID(directory); items = items.filter { ($0.directoryID ?? GameDirectory.defaultID) == id } }
            return request.page(items.sorted { $0.id.uuidString < $1.id.uuidString }.map { instanceValue($0, paths: paths) })
        case "selected": return .object(["id": .text(state.selectedInstanceID?.uuidString)])
        case "versions":
            let catalog = try await GameInstaller(paths: paths, downloader: downloader).catalog()
            return request.page(catalog.versions.filter { request.flag("snapshots") || $0.type == "release" }.map { .object(["id": .string($0.id), "type": .string($0.type)]) })
        case "create":
            let created = try service.create(name: request.required("name"), game: request.required("game"), selections: selections(request), directoryID: directoryID(request.required("directory")), dryRun: request.dryRun)
            if request.dryRun || request.flag("no-install") { return .object(["dryRun": .bool(request.dryRun), "instance": instanceValue(created, paths: paths.including(created))]) }
            output.event("instanceCreated", .object(["id": .string(created.id.uuidString)]))
            do { return instanceValue(try await service.install(created.id, downloader: downloader, progress: { output.progress($0) }), paths: paths.including(created)) }
            catch { throw OperationFailure("INSTALLATION_FAILED", error.localizedDescription, nextActions: [.init(["instance", "install", created.id.uuidString])], details: .object(["instanceID": .string(created.id.uuidString)])) }
        default: break
        }
        let instance: GameInstance
        if action == "show" {
            guard (request.operands.isEmpty ? 0 : 1) + (request.string("name") == nil ? 0 : 1) == 1 else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t79f4a3aa9493.localized) }
            instance = try service.resolve(id: request.operands.first.map(uuid), name: request.string("name"))
        } else { instance = try service.resolve(id: uuid(request.operand())) }
        let id = instance.id
        switch action {
        case "show": return instanceValue(instance, paths: paths)
        case "select":
            if !request.dryRun { try service.select(id) }
            return .object(["id": .string(id.uuidString), "dryRun": .bool(request.dryRun)])
        case "rename": return instanceValue(try service.edit(id, name: request.operand(1), dryRun: request.dryRun), paths: paths)
        case "favorite":
            guard let enabled = Bool(try request.operand(1)) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t188ae1e6f458.localized) }
            return instanceValue(try service.edit(id, favorite: enabled, dryRun: request.dryRun), paths: paths)
        case "icon":
            guard [request.string("file") != nil, request.string("glyph") != nil, request.flag("reset")].filter({ $0 }).count == 1 else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tf996e1aeec0d.localized) }
            let icon: InstanceIconChange
            if let file = request.string("file") { icon = .image(try readInput(file, maximumBytes: 8 * 1024 * 1024)) }
            else if let name = request.string("glyph") {
                guard let glyph = InstanceIconGlyph(rawValue: name), let tint = InstanceIconTint(rawValue: request.string("tint") ?? "slate") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.te8f93a97f4a5.localized) }
                icon = .style(.init(glyph: glyph, tint: tint))
            } else { icon = .reset }
            return instanceValue(try service.edit(id, icon: icon, dryRun: request.dryRun), paths: paths)
        case "remove":
            if !request.dryRun { try service.remove(id) }
            return .object(["id": .string(id.uuidString), "dryRun": .bool(request.dryRun), "instanceDirectory": .string(paths.instance(id).path), "retainsExternalGameDirectory": .bool(instance.runDirectory != .isolated && instance.runDirectory != nil)])
        case "install", "repair":
            if request.dryRun { return .object(["dryRun": .bool(true), "instance": instanceValue(instance, paths: paths)]) }
            return instanceValue(try await service.install(id, repair: action == "repair", downloader: downloader, progress: { output.progress($0) }), paths: paths)
        case "component list":
            let backup = try await InstanceComponents(paths: paths).backup(for: id)
            return .object(["components": .array(instance.loaderSelections.map { .object(["loader": .string($0.loader.rawValue), "version": .string($0.version)]) }), "backup": .text(backup?.title), "unavailableReason": .text(InstanceComponents.unavailableReason(instance))])
        case "component versions":
            guard let loader = LoaderKind(rawValue: try request.operand(1)) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tecaf531d009c.localized) }
            return request.page(try await GameInstaller(paths: paths).loaderVersions(loader, game: instance.gameVersion).map(Value.string))
        case "component set", "component restore":
            let service = InstanceComponents(paths: paths, downloader: downloader), selected = try selections(request)
            if action == "component set", let issue = LoaderCompatibility.combinationIssue(selected.map(\.loader), game: instance.gameVersion) { throw OperationFailure("INVALID_ARGUMENT", issue) }
            if request.dryRun { return .object(["dryRun": .bool(true), "id": .string(id.uuidString), "components": .array(selected.map { .object(["loader": .string($0.loader.rawValue), "version": .string($0.version)]) })]) }
            let saved = try await action == "component restore" ? service.restore(instance) : service.change(instance, selections: selected, concurrency: state.settings.concurrentDownloads, progress: { output.progress($0) })
            return instanceValue(saved.instances.first { $0.id == id }!, paths: paths)
        case "copy":
            let copier = InstanceCopier(paths: paths)
            let preview = try await copier.preview(instanceID: id, name: request.required("name"), directoryID: directoryID(request.required("directory")), options: .init(includeWorlds: !request.flag("without-worlds"), includeBackups: request.flag("with-backups")))
            var result: [String: Value] = ["dryRun": .bool(request.dryRun), "instanceID": .string(preview.copy.id.uuidString), "source": .string(preview.sourceGame.path), "destination": .string(preview.destination.path), "files": .integer(preview.fileCount), "bytes": .integer(preview.bytes)]
            if !request.dryRun {
                let copied = try await copier.copy(preview) { output.event("progress", .object(["phase": .string($0.phase.rawValue), "completed": .integer($0.completed), "total": .integer($0.total)])) }
                result["warning"] = .text(copied.warning); result["preservedCopy"] = .text(copied.preservedCopy?.path)
            }
            return .object(result)
        case "move":
            let mover = InstanceMover(paths: paths), preview = try await mover.preview(instanceID: id, directoryID: directoryID(request.required("directory")))
            var result: [String: Value] = ["dryRun": .bool(request.dryRun), "instanceID": .string(id.uuidString), "source": .string(preview.sourceDirectory.path), "destination": .string(preview.destination.path), "files": .integer(preview.fileCount), "bytes": .integer(preview.bytes), "retainedGameDirectory": .text(preview.retainedGameDirectory?.path)]
            if !request.dryRun {
                let moved = try await mover.move(preview) { output.event("progress", .object(["phase": .string($0.phase.rawValue), "bytesCopied": .integer($0.bytesCopied), "totalBytes": .integer($0.totalBytes)])) }
                result["warning"] = .text(moved.warning); result["preservedFiles"] = .array(moved.preservedFiles.map { .string($0.path) })
            }
            return .object(result)
        case "export":
            let destination = URL(fileURLWithPath: try request.operand(1))
            try requireNewFile(destination)
            if !request.dryRun {
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
                try await InstanceTransfer(paths: paths).export(instance, to: destination, format: InstanceExportFormat(rawValue: request.string("format") ?? "ruri")!, includeWorlds: !request.flag("without-worlds"), progress: { output.progress($0) })
            }
            return .object(["file": .string(destination.path), "dryRun": .bool(request.dryRun)])
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.td578c368dab6.localized)
        }
    }
    static func instanceValue(_ item: GameInstance, paths: LauncherPaths) -> Value {
        .object(["id": .string(item.id.uuidString), "name": .string(item.name), "gameVersion": .string(item.gameVersion), "installed": .bool(item.installed), "favorite": .bool(item.favorite),
            "components": .array(item.loaderSelections.map { .object(["loader": .string($0.loader.rawValue), "version": .string($0.version)]) }),
            "directoryID": .string((item.directoryID ?? GameDirectory.defaultID).uuidString), "runDirectory": .string((item.runDirectory ?? .isolated).rawValue),
            "instanceDirectory": .string(paths.instance(item.id).path), "gameDirectory": .string(paths.game(item.id).path), "hasCustomIcon": .bool(item.iconPNG != nil),
            "iconGlyph": .text(item.iconStyle?.glyph.rawValue), "iconTint": .text(item.iconStyle?.tint.rawValue), "issue": .text(item.repositoryIssue)])
    }
    static func selections(_ request: CommandRequest) throws -> [LoaderSelection] {
        guard case .array(let values) = request.options["component"] else { return [] }
        let result = try values.map { value -> LoaderSelection in
            let parts = (value.string ?? "").split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let loader = LoaderKind(rawValue: parts[0]), loader != .vanilla, !parts[1].isEmpty else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tc7720bf2a0d4.localized) }
            return .init(loader: loader, version: parts[1])
        }
        guard Set(result.map(\.loader)).count == result.count else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t46989dde4470.localized) }; return result
    }
    static func directoryID(_ input: String) throws -> UUID { input == "default" ? GameDirectory.defaultID : try uuid(input) }
    @MainActor static func context(_ request: CommandRequest) async throws -> (PersistentState, LauncherPaths, DownloadManager) {
        let base = basePaths(request), state = try StateStore.load(base), paths = base.configured(with: state)
        let downloader = DownloadManager()
        var source = state.settings.downloadSource ?? .automatic
        if let override = ProcessInfo.processInfo.environment["RURI_DOWNLOAD_SOURCE"] {
            guard let selected = DownloadSource(rawValue: override) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t733e25583e8d.localized) }; source = selected
        }
        await NetworkRouting.shared.configure(source)
        await downloader.configure(concurrency: state.settings.concurrentDownloads, cache: DownloadCache(paths: base))
        return (state, paths, downloader)
    }
    static func requireNewFile(_ file: URL) throws {
        guard !FileManager.default.fileExists(atPath: file.path), (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) == nil else { throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.t121c67f22040.localized) }
    }
}
