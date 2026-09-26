import RuriLocalization
import Foundation

public struct InstanceService: Sendable {
    public let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public func resolve(id: UUID? = nil, name: String? = nil) throws -> GameInstance {
        let items = try StateStore.load(paths).instances.filter { item in id.map { item.id == $0 } ?? (name.map { item.name == $0 } ?? false) }
        guard !items.isEmpty else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t491b2168687b.localized) }
        guard items.count == 1 else { throw OperationFailure("AMBIGUOUS_TARGET", Messages.CLIInterface.tfe6f797e1938.localized, details: .array(items.map { .object(["id": .string($0.id.uuidString), "name": .string($0.name)]) })) }
        return items[0]
    }
    public func create(name: String, game: String, selections: [LoaderSelection], directoryID: UUID, dryRun: Bool = false) throws -> GameInstance {
        try Self.validateName(name)
        guard !game.isEmpty, !game.contains("/"), !game.contains("\\"), !game.contains("\0") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t79de4634dcb4.localized) }
        if let issue = LoaderCompatibility.combinationIssue(selections.map(\.loader), game: game) { throw OperationFailure("INVALID_ARGUMENT", issue) }
        let state = try StateStore.load(paths), configured = paths.configured(with: state)
        guard directoryID == GameDirectory.defaultID || state.gameDirectories?.contains(where: { $0.id == directoryID }) == true else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t70a45a4240d8.localized) }
        var instance = GameInstance(name: name, gameVersion: game)
        instance.setLoaderSelections(selections); instance.launchOverrides = .init(); instance.directoryID = directoryID
        instance.runDirectory = (state.settings.isolationPolicy ?? .always).directory(loader: instance.loader)
        instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: configured)
        if !dryRun {
            try StateStore.updateIfChanged(paths) { latest in
                let current = paths.configured(with: latest)
                guard directoryID == GameDirectory.defaultID || latest.gameDirectories?.contains(where: { $0.id == directoryID }) == true else { throw OperationFailure("STATE_CONFLICT", Messages.CLIInterface.t17574d1bad8e.localized) }
                instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: current)
                latest.instances.append(instance)
            }
        }
        return instance
    }
    @discardableResult public func select(_ id: UUID) throws -> PersistentState {
        try StateStore.updateIfChanged(paths) { state in
            guard state.instances.contains(where: { $0.id == id }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t491b2168687b.localized) }
            state.selectedInstanceID = id
        }
    }
    @discardableResult public func edit(_ id: UUID, name: String? = nil, favorite: Bool? = nil, icon: InstanceIconChange = .unchanged, dryRun: Bool = false) throws -> GameInstance {
        if let name { try Self.validateName(name) }
        if case .image(let data) = icon { try InstanceIconImage.validate(data) }
        var result: GameInstance?
        func change(_ state: inout PersistentState) throws {
            guard let index = state.instances.firstIndex(where: { $0.id == id }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t491b2168687b.localized) }
            if let name { state.instances[index].name = name }
            if let favorite { state.instances[index].favorite = favorite }
            switch icon {
            case .unchanged: break
            case .reset: state.instances[index].iconPNG = nil; state.instances[index].iconStyle = nil
            case .image(let data): state.instances[index].iconPNG = data
            case .style(let style): state.instances[index].iconPNG = nil; state.instances[index].iconStyle = style
            }
            result = state.instances[index]
        }
        if dryRun { var state = try StateStore.load(paths); try change(&state) }
        else { try StateStore.updateIfChanged(paths, change) }
        return result!
    }
    public func install(_ id: UUID, repair: Bool = false, downloader: DownloadManager = DownloadManager(), progress: @Sendable @escaping (InstallProgress) async -> Void = { _ in }) async throws -> GameInstance {
        let state = try StateStore.load(paths), paths = paths.configured(with: state), requested = try resolve(id: id)
        let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
        defer { withExtendedLifetime(lease) {} }
        let installer = GameInstaller(paths: paths, downloader: downloader)
        if repair { try await installer.repair(requested, concurrency: state.settings.concurrentDownloads, progress: progress); return requested }
        let result = try await installer.install(requested, concurrency: state.settings.concurrentDownloads, progress: progress)
        return try recordInstallation(result, requested: requested)
    }
    public func recordInstallation(_ result: GameInstance, requested: GameInstance) throws -> GameInstance {
        let id = requested.id
        let saved = try StateStore.updateIfChanged(paths) { state in
            guard let index = state.instances.firstIndex(where: { $0.id == id }) else { throw OperationFailure("STATE_CONFLICT", Messages.CLIInterface.tb199229434bb.localized) }
            state.instances[index] = try state.instances[index].applyingInstallation(result, requested: requested)
        }
        return saved.instances.first { $0.id == id }!
    }
    @discardableResult public func remove(_ id: UUID) throws -> PersistentState {
        let state = try StateStore.load(paths), configured = paths.configured(with: state), instance = try resolve(id: id)
        if instance.repositoryVersionID != nil { return try MinecraftFolderStore.trashVersion(id, paths: paths) }
        let lease = try GameRunLease.acquire(paths: configured, instanceID: id)
        defer { withExtendedLifetime(lease) {} }
        let source = configured.instance(id)
        var trashed: NSURL?
        do {
            return try StateStore.updateIfChanged(paths) { state in
                guard let latest = state.instances.first(where: { $0.id == id }), latest.directoryID == instance.directoryID,
                      latest.lastInstanceMoveID == instance.lastInstanceMoveID else { throw OperationFailure("STATE_CONFLICT", Messages.CLIInterface.t7d732629b332.localized) }
                if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.trashItem(at: source, resultingItemURL: &trashed) }
                state.instances.removeAll { $0.id == id }
                if state.selectedInstanceID == id { state.selectedInstanceID = state.instances.first?.id }
            }
        } catch {
            if let trashed, !FileManager.default.fileExists(atPath: source.path) { try? FileManager.default.moveItem(at: trashed as URL, to: source) }
            throw error
        }
    }
    private static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 1024, !name.contains("\0") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t97013cab62b8.localized) }
    }
}

public enum InstanceIconChange: Sendable {
    case unchanged, reset, image(Data), style(InstanceIconStyle)
}
