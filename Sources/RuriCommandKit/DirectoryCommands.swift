import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageDirectory(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (state, paths, _) = try await context(request), action = request.spec.path.dropFirst().joined(separator: " ")
        func entries(_ state: PersistentState) -> [Value] {
            [.object(["id": .string(GameDirectory.defaultID.uuidString), "name": .string("default"), "path": .string(paths.root.path), "layout": .string("managed"), "detached": .bool(false)])] +
            (state.gameDirectories ?? []).map { directoryValue($0, detached: false) } + (state.detachedMinecraftFolders ?? []).map { directoryValue($0.directory, detached: true) }
        }
        switch action {
        case "list": return request.page(entries(state))
        case "selected": return .object(["id": .string((state.selectedDirectoryID ?? GameDirectory.defaultID).uuidString)])
        case "scan":
            let catalog = try await MinecraftDirectoryReader().scan(URL(fileURLWithPath: request.operand()))
            return request.page(catalog.versions.map { item in .object(["id": .string(item.id), "gameVersion": .text(item.gameVersion), "issue": .text(item.issue),
                "components": .array(item.components.map { .object(["name": .string($0.name), "version": .string($0.version)]) }),
                "locations": .array(item.gameLocations.map { .object(["id": .string($0.id), "path": .string($0.directory.path), "available": .bool($0.available)]) }),
                "suggestedLocation": .text(item.suggestedLocationID), "warnings": .array(item.warnings.map(Value.string))]) })
        case "add":
            let url = URL(fileURLWithPath: try request.operand()), name = try request.required("name"), minecraft = request.string("layout") != "managed"
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t5efd67648f0d.localized) }
            if request.dryRun {
                if minecraft { _ = try await MinecraftDirectoryReader().scan(url) }
                else {
                    guard try FileManager.default.contentsOfDirectory(atPath: url.path).allSatisfy({ $0 == ".DS_Store" }) else { throw OperationFailure("DIRECTORY_NOT_EMPTY", Messages.CLIInterface.t8ba03aeb3548.localized) }
                }
                return .object(["dryRun": .bool(true), "path": .string(url.path), "name": .string(name), "layout": .string(minecraft ? "minecraft" : "managed")])
            }
            let saved = try minecraft ? MinecraftFolderStore.add(name: name, url: url, paths: paths) : GameDirectoryStore.add(name: name, url: url, paths: paths)
            return .object(["selectedDirectoryID": .text(saved.selectedDirectoryID?.uuidString), "directories": .array(entries(saved))])
        case "run get", "run set", "run relocate":
            let id = try uuid(request.operand()), instance = try InstanceService(paths: paths).resolve(id: id)
            if action == "run get" { return .object(["id": .string(id.uuidString), "mode": .string((instance.runDirectory ?? .isolated).rawValue), "path": .string(paths.game(id).path), "customDirectory": .text(instance.customRunDirectory?.url.path)]) }
            if action == "run relocate" {
                let service = CustomRunDirectoryRelocation(paths: paths), preview = try await service.preview(instanceID: id, target: URL(fileURLWithPath: request.operand(1)))
                if !request.dryRun { _ = try await service.apply(preview) }
                return .object(["dryRun": .bool(request.dryRun), "source": .string(preview.source.path), "target": .string(preview.target.path), "instances": .array(preview.instances.map { .string($0.id.uuidString) })])
            }
            guard let mode = GameRunDirectory(rawValue: try request.operand(1)), mode == .custom || request.string("path") == nil else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tdc5f6e9debdb.localized) }
            let service = GameRunDirectoryChange(paths: paths), preview: GameRunDirectoryChangePreview
            if request.dryRun { preview = try await service.inspect(instanceID: id, target: mode, customPath: request.string("path").map { URL(fileURLWithPath: $0) }) }
            else {
                let custom = try request.string("path").map { try CustomRunDirectory.register(at: URL(fileURLWithPath: $0), paths: paths) }
                preview = try await service.preview(instanceID: id, target: mode, customDirectory: custom)
                if request.flag("copy") { _ = try await service.copyToEmpty(preview) { output.event("progress", .object(["phase": .string($0.phase.rawValue), "completed": .integer($0.completed), "total": .integer($0.total)])) } }
                else { _ = try await service.useExisting(preview) }
            }
            return .object(["dryRun": .bool(request.dryRun), "source": .string(preview.source.path), "target": .string(preview.target.path), "sourceFiles": .integer(preview.sourceFileCount),
                "targetFiles": .integer(preview.targetFileCount), "sourceBytes": .integer(preview.sourceBytes), "targetBytes": .integer(preview.targetBytes), "canCopy": .bool(preview.canCopyToTarget),
                "copyIssue": .text(preview.copyIssue), "otherInstances": .array(preview.otherInstances.map(Value.string))])
        default: break
        }
        let id = try directoryID(request.operand())
        guard id == GameDirectory.defaultID || (state.gameDirectories ?? []).contains(where: { $0.id == id }) || (action == "restore" && state.detachedMinecraftFolders?.contains(where: { $0.id == id }) == true) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t70a45a4240d8.localized) }
        if request.dryRun { return .object(["dryRun": .bool(true), "id": .string(id.uuidString), "action": .string(action), "instances": .array(state.instances.filter { ($0.directoryID ?? GameDirectory.defaultID) == id }.map { .string($0.id.uuidString) })]) }
        let saved: PersistentState
        switch action {
        case "select": saved = try GameDirectoryStore.select(id, paths: paths)
        case "refresh": saved = try MinecraftFolderStore.refresh(id, paths: paths)
        case "rename": saved = try GameDirectoryStore.rename(id, name: request.operand(1), paths: paths)
        case "relocate": saved = try GameDirectoryStore.relocate(id, to: URL(fileURLWithPath: request.operand(1)), paths: paths)
        case "remove": saved = try GameDirectoryStore.remove(id, paths: paths)
        case "restore": saved = try MinecraftFolderStore.restore(id, from: URL(fileURLWithPath: request.operand(1)), paths: paths)
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t9a582e74d089.localized)
        }
        return .object(["id": .string(id.uuidString), "directories": .array(entries(saved))])
    }
    static func directoryValue(_ directory: GameDirectory, detached: Bool) -> Value {
        .object(["id": .string(directory.id.uuidString), "name": .string(directory.name), "path": .string(directory.url.path),
            "layout": .string(directory.isMinecraft ? "minecraft" : "managed"), "detached": .bool(detached), "available": .bool((try? directory.validateAvailability()) != nil)])
    }
}
