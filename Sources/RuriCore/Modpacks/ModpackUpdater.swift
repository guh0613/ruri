import RuriLocalization
import Foundation

public actor ModpackUpdater {
    let paths: LauncherPaths
    let downloader: DownloadManager
    public init(paths: LauncherPaths, downloader: DownloadManager = DownloadManager()) { self.paths = paths; self.downloader = downloader }

    public func prepare(_ prepared: PreparedInstanceImport, for requested: GameInstance, keepJVMArguments: Bool = false,
                        content: [ContentInstallation] = [], concurrency: Int = 8,
                        progress: @Sendable @escaping (InstallProgress) async -> Void = { _ in }) async throws -> PreparedModpackUpdate {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard let instance = state.instances.first(where: { $0.id == requested.id }) else { throw RuriError.message(Messages.CoreModpackUpdater.instanceRemoved) }
        _ = try instance.applyingInstallation(requested, requested: requested)
        guard let pack = try ModpackRegistry.load(paths: current, instanceID: instance.id) else { throw RuriError.message(Messages.CoreModpackUpdater.missingPackSource) }
        guard prepared.modpack != nil, !prepared.includesInstallation else { throw RuriError.message(Messages.CoreModpackUpdater.invalidPackSelection) }
        if let origin = pack.origin, let incoming = prepared.modpack?.origin, origin.projectID != nil, incoming.projectID != nil {
            guard origin.provider == incoming.provider, origin.projectID == incoming.projectID else { throw RuriError.message(Messages.CoreModpackUpdater.wrongPackProject) }
        }
        let lease = try GameRunLease.acquire(paths: current, instanceID: instance.id)
        defer { withExtendedLifetime(lease) {} }
        try requireIndependent(instance, paths: current)
        let baselineData = try RunDirectoryCopyGuard.read(current.instance(instance.id).appendingPathComponent("modpack-state.json"), limit: 64 * 1024 * 1024)
        let manifestData = try RunDirectoryCopyGuard.read(current.manifest(instance.id), limit: 32 * 1024 * 1024)
        let id = UUID(), work = try LauncherPaths.safePath("modpack-update-work/" + id.uuidString, within: current.instance(instance.id))
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let resources = try current.resources(for: instance)
            for (name, destination) in [("libraries", resources.libraries), ("assets", resources.assets), ("cache", paths.cache), ("runtimes", paths.runtimes)] {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: work.appendingPathComponent(name), withDestinationURL: destination)
            }
            let staging = LauncherPaths(root: work), transfer = InstanceTransfer(paths: staging)
            try await transfer.completeFiles(prepared, downloader: downloader, concurrency: concurrency, progress: progress)
            let candidate = try await transfer.install(prepared, name: instance.name, importJVMArguments: keepJVMArguments, content: content, installing: { value, _ in value })
            guard var incoming = try ModpackRegistry.load(paths: staging, instanceID: candidate.id) else { throw RuriError.message(Messages.CoreModpackUpdater.missingFileManifest) }
            if incoming.origin == nil, incoming.format == pack.format, let origin = pack.origin {
                incoming = .init(format: incoming.format, name: incoming.name, version: incoming.version,
                                 origin: .init(provider: origin.provider, projectID: origin.projectID, fileAPI: origin.fileAPI), settings: incoming.settings, files: incoming.files)
            }
            let records = try await ContentManager(paths: current, instanceID: instance.id).records()
            let incomingRecords = try await ContentManager(paths: staging, instanceID: candidate.id).records()
            let reserved = Set(MinecraftGameDataFiles.reservedNames(paths: current, instanceID: instance.id).map(MinecraftGameDataFiles.key))
            let changes = try ModpackUpdatePlanner.changes(from: pack, to: incoming, game: current.game(instance.id), records: records).filter {
                !reserved.contains(MinecraftGameDataFiles.key(String($0.id.split(separator: "/").first ?? "")))
            }
            return .init(id: id, instance: instance, current: pack, incoming: incoming, changes: changes, workspace: work, candidate: candidate,
                         baselineData: baselineData, manifestData: manifestData, contentRecords: incomingRecords, keepJVMArguments: keepJVMArguments)
        } catch { try? FileManager.default.removeItem(at: work); throw error }
    }
    public func discard(_ plan: PreparedModpackUpdate) { try? FileManager.default.removeItem(at: plan.workspace) }

    public func apply(_ plan: PreparedModpackUpdate, keepingLocal: Set<String>, concurrency: Int = 8,
                      progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> PersistentState {
        let downloader = downloader
        return try await apply(plan, keepingLocal: keepingLocal, installing: { candidate, staging in
            try await GameInstaller(paths: staging, downloader: downloader, protectExistingFiles: true).install(candidate, concurrency: concurrency, progress: progress)
        }, progress: progress)
    }
    func apply(_ plan: PreparedModpackUpdate, keepingLocal: Set<String>, installing: @Sendable (GameInstance, LauncherPaths) async throws -> GameInstance,
               progress: @Sendable @escaping (InstallProgress) async -> Void = { _ in }) async throws -> PersistentState {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard let instance = state.instances.first(where: { $0.id == plan.instance.id }) else { throw RuriError.message(Messages.CoreModpackUpdater.instanceRemoved) }
        _ = try instance.applyingInstallation(plan.instance, requested: plan.instance)
        let lease = try GameRunLease.acquire(paths: current, instanceID: instance.id)
        defer { withExtendedLifetime(lease) {} }
        let records = try await ContentManager(paths: current, instanceID: instance.id).records()
        try lease.excludeLocationOperations()
        try validate(plan, instance: instance, paths: current)
        let staging = LauncherPaths(root: plan.workspace)
        let installed = try await installing(plan.candidate, staging)
        var manifest = try await GameInstaller(paths: staging).loadManifest(installed)
        let client = try staging.clientJar(manifest.jar ?? installed.gameVersion, instance: installed)
        let clientID = instance.repositoryVersionID ?? "ruri-\(instance.id.uuidString)-\(installed.gameVersion)"
        let targetClient = try current.clientJar(clientID, instance: instance)
        manifest.id = instance.repositoryVersionID ?? manifest.id; manifest.jar = clientID; manifest.inheritsFrom = nil
        let replacements = [staging.libraries.path: "${library_directory}", staging.assets.path: "${assets_root}",
                            staging.game(installed.id).path: "${game_directory}", staging.instance(installed.id).appendingPathComponent("natives").path: "${natives_directory}",
                            client.path: targetClient.path, client.deletingLastPathComponent().path: targetClient.deletingLastPathComponent().path]
        func rewrite(_ value: String) throws -> String {
            let result = MinecraftInstallationCopy.rewrite(value, replacements: replacements)
            guard !result.contains(plan.workspace.path) else { throw RuriError.message(Messages.CoreModpackUpdater.unmigratableTemporaryPath) }
            return result
        }
        func argument(_ value: LaunchArgument) throws -> LaunchArgument {
            switch value { case .text(let text): .text(try rewrite(text)); case .conditional(let rules, let values): .conditional(rules, try values.map(rewrite)) }
        }
        if var arguments = manifest.arguments { arguments.game = try arguments.game?.map(argument); arguments.jvm = try arguments.jvm?.map(argument); manifest.arguments = arguments }
        if let legacy = manifest.minecraftArguments { manifest.minecraftArguments = try ArgumentTokenizer.join(ArgumentTokenizer.split(legacy).map(rewrite)) }
        let latestState = try StateStore.load(paths)
        guard let latest = latestState.instances.first(where: { $0.id == instance.id }) else { throw RuriError.message(Messages.CoreModpackUpdater.instanceRemovedAfterPreview) }
        _ = try latest.applyingInstallation(instance, requested: instance)
        try validate(plan, instance: latest, paths: current)
        var updated = latest
        updated.gameVersion = installed.gameVersion; updated.loader = installed.loader; updated.loaderVersion = installed.loaderVersion
        updated.supportedJavaMajors = installed.supportedJavaMajors; updated.packLibraries = installed.packLibraries
        let components = installed.loaderSelections.map { MinecraftDirectoryComponent(name: $0.loader.title, version: $0.version) }
        updated.repositoryComponents = components
        if let imported = latest.importedInstallation { updated.importedInstallation = .init(sourceVersionID: imported.sourceVersionID, components: components) }
        if latest.extraJVMArguments == plan.current.settings.extraJVMArguments { updated.extraJVMArguments = installed.extraJVMArguments }
        if latest.extraGameArguments == plan.current.settings.extraGameArguments { updated.extraGameArguments = installed.extraGameArguments }
        if var overrides = latest.launchOverrides {
            // Imports leave arguments the pack does not set inherited, so an
            // empty pack value corresponds to inheritance here.
            func packValue(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }
            if overrides.jvmArguments == packValue(plan.current.settings.extraJVMArguments) { overrides.jvmArguments = packValue(installed.extraJVMArguments) }
            if overrides.gameArguments == packValue(plan.current.settings.extraGameArguments) { overrides.gameArguments = packValue(installed.extraGameArguments) }
            updated.launchOverrides = overrides
        }
        updated.lastModpackUpdateID = plan.id
        let publish = plan.workspace.appendingPathComponent("publish")
        try FileManager.default.createDirectory(at: publish, withIntermediateDirectories: true)
        var files: [ModpackReplacement] = []
        for change in plan.changes where !keepingLocal.contains(change.id) {
            if let previous = change.previousPath, previous != change.targetPath {
                files.append(.init(target: .init(scope: .game, path: previous), group: "game:" + change.id, source: nil))
            }
            if let target = change.targetPath, let incoming = change.incoming {
                let source = try LauncherPaths.safePath(incoming.path, within: staging.game(installed.id))
                guard try ModpackUpdatePlanner.digest(source) == incoming.sha1 else { throw RuriError.message(Messages.CoreModpackUpdater.updateFilesChangedAfterPreview(incoming.path)) }
                files.append(.init(target: .init(scope: .game, path: target), group: "game:" + change.id, source: source))
            }
        }
        func data(_ value: Data?, path: String, scope: ModpackUpdateTarget.Scope = .metadata) throws {
            let source = value.map { _ in publish.appendingPathComponent(UUID().uuidString) }
            if let value, let source { try value.write(to: source) }
            files.append(.init(target: .init(scope: scope, path: path), group: "installation", source: source))
        }
        var document = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as! [String: Any]
        document["clientVersion"] = installed.gameVersion; document["patches"] = components.map { ["id": $0.name.lowercased(), "version": $0.version] }
        try data(JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted]),
                 path: latest.repositoryVersionID.map { $0 + ".json" } ?? "version.json", scope: latest.repositoryVersionID == nil ? .metadata : .version)
        files.append(.init(target: .init(scope: .resources, path: "versions/\(clientID)/\(clientID).jar"), group: "installation", source: client))
        var pack = plan.incoming; pack.settings.id = latest.id
        try data(JSONEncoder().encode(pack), path: "modpack-state.json")
        let content = try ModpackUpdateStore.mergedRecords(plan.contentRecords + records, replacements: files, instance: latest, paths: current)
        try data(JSONEncoder().encode(content), path: "content.json", scope: .content)
        let sourceMetadata = staging.instance(installed.id).appendingPathComponent("source-mcbbs.packmeta")
        try data(FileManager.default.fileExists(atPath: sourceMetadata.path) ? RunDirectoryCopyGuard.read(sourceMetadata, limit: 32 * 1024 * 1024) : nil, path: "source-mcbbs.packmeta")
        try Task.checkCancellation()
        await progress(InstallProgress(Messages.CoreModpackUpdater.applyingUpdate, total: files.count))
        let saved = try ModpackUpdateStore.commit(id: plan.id, original: latest, updated: updated, replacements: files, paths: current)
        discard(plan)
        return saved
    }
    public func rollback(_ requested: GameInstance) throws -> (state: PersistentState, preservedFiles: Int) {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard let latest = state.instances.first(where: { $0.id == requested.id }) else { throw RuriError.message(Messages.CoreModpackUpdater.instanceRemovedAfterPreview) }
        let lease = try GameRunLease.acquire(paths: current, instanceID: latest.id)
        defer { withExtendedLifetime(lease) {} }
        try lease.excludeLocationOperations()
        return try ModpackUpdateStore.rollback(instance: latest, paths: current)
    }
    private func validate(_ plan: PreparedModpackUpdate, instance: GameInstance, paths: LauncherPaths) throws {
        try paths.validateBinding(instance)
        try requireIndependent(instance, paths: paths)
        guard try RunDirectoryCopyGuard.read(paths.manifest(instance.id), limit: 32 * 1024 * 1024) == plan.manifestData,
              try RunDirectoryCopyGuard.read(paths.instance(instance.id).appendingPathComponent("modpack-state.json"), limit: 64 * 1024 * 1024) == plan.baselineData else {
            throw RuriError.message(Messages.CoreModpackUpdater.previewConfigurationChanged)
        }
        for item in plan.changes {
            for (path, expected) in item.observed {
                guard try ModpackUpdatePlanner.digest(LauncherPaths.safePath(path, within: paths.game(instance.id))) == expected else {
                    throw RuriError.message(Messages.CoreModpackUpdater.filesChangedAfterPreview(path))
                }
            }
        }
    }
    private func requireIndependent(_ instance: GameInstance, paths: LauncherPaths) throws {
        guard let id = instance.repositoryVersionID else { return }
        let reader = MinecraftDirectoryReader(), catalog = try reader.scanNow(paths.directoryRoot(paths.directoryID(for: instance.id)))
        for other in catalog.versions where other.id != id && other.issue == nil {
            let resolution = try reader.resolveManifestNow(other, in: catalog)
            if resolution.manifest.jar == id || resolution.sourceManifests.contains(where: { $0.url == paths.manifest(instance.id) }) {
                throw RuriError.message(Messages.CoreModpackUpdater.dependencyConflict(String(describing: other.id)))
            }
        }
    }
}
