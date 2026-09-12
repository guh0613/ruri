import RuriLocalization
import Foundation

struct PreparedMinecraftInstallation: Sendable {
    let root: URL
    let plan: MinecraftInstallationCopy
    let fileCount: Int
    let byteCount: Int64
    static func portableCopy(_ instance: GameInstance) -> GameInstance {
        var copy = instance; copy.repositoryVersionID = "game"; copy.importedInstallation = nil; return copy
    }
    static func capture(_ source: URL, in workspace: URL, instance: GameInstance, paths: LauncherPaths) throws -> Self {
        let root = workspace.appendingPathComponent("installation")
        try FileTree.copy(from: source, to: root)
        let plan = try MinecraftInstallationCopy.read(instance: instance, copy: portableCopy(instance), paths: paths, portable: true, installationRoot: root)
        let files = try FileTree.entries(in: root).filter { !$0.directory }
        return .init(root: root, plan: plan, fileCount: files.count, byteCount: files.reduce(0) { $0 + $1.size })
    }
    func validate(instance: GameInstance, paths: LauncherPaths) throws {
        let actual = try MinecraftInstallationCopy.read(instance: instance, copy: Self.portableCopy(instance), paths: paths, portable: true, installationRoot: root)
        guard actual.manifest == plan.manifest, actual.client == plan.client, actual.resources == plan.resources,
              actual.inputs == plan.inputs, actual.generatedResources == plan.generatedResources, actual.sourceManifests == plan.sourceManifests else {
            throw RuriError.message(Messages.CoreCompleteInstancePack.installationFilesChangedDuringPreview)
        }
    }
}

extension MinecraftInstallationCopy {
    func install(_ instance: GameInstance, at paths: LauncherPaths) async throws {
        let resources = try paths.resources(for: instance)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: self.manifest)
        try await write(resourceRoot: resources.root, clientFile: paths.clientJar(manifest.jar ?? instance.gameVersion, instance: instance),
                        manifestFile: paths.manifest(instance.id), metadata: paths.instance(instance.id), validate: { try paths.validateInstanceLocation(instance.id) })
    }

    func write(resourceRoot: URL, clientFile: URL, manifestFile: URL, metadata: URL, validate: @Sendable () throws -> Void = {}, progress: @Sendable (InstallProgress) -> Void = { _ in }) async throws {
        try validate()
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: clientFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunDirectoryFileCopy.file(client.source, to: clientFile, validate: validate) { _ in }
        try MinecraftInstallationFiles.requireResource(clientFile, sha1: client.sha1, size: client.size)
        var completed = 1
        for resource in resources {
            try await MinecraftInstallationFiles.copyResource(resource, root: resourceRoot, validate: validate, progress: { _ in })
            completed += 1; progress(.init(Messages.CoreCompleteInstancePack.copyingInstallationFiles, completed: completed, total: fileCount))
        }
        for (path, data) in generatedResources {
            let temporary = metadata.appendingPathComponent("resource-" + UUID().uuidString)
            try data.write(to: temporary, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let resource = Resource(source: temporary, path: path, sha1: Self.sha1(data), size: Int64(data.count))
            try await MinecraftInstallationFiles.copyResource(resource, root: resourceRoot, validate: validate, progress: { _ in })
            completed += 1; progress(.init(Messages.CoreCompleteInstancePack.copyingInstallationFiles, completed: completed, total: fileCount))
        }
        try FileManager.default.createDirectory(at: manifestFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try validate()
        try manifest.write(to: manifestFile, options: .withoutOverwriting)
        for data in sourceManifests.values { try Self.saveOriginal(data, in: metadata) }
    }
    static func saveOriginal(_ data: Data, in metadata: URL) throws {
        let file = try LauncherPaths.safePath("source-manifests/" + sha1(data) + ".json", within: metadata)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) { try data.write(to: file, options: .withoutOverwriting) }
    }
    static func retainOriginals(from metadata: URL, to destination: URL) throws {
        let root = try LauncherPaths.safePath("source-manifests", within: metadata)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let files = try FileTree.entries(in: root).filter { !$0.directory }
        guard files.count <= 1024, files.reduce(Int64(0), { $0 + $1.size }) <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreCompleteInstancePack.sourceManifestExportLimitExceeded) }
        for file in files { try saveOriginal(RunDirectoryCopyGuard.read(file.url, limit: 8_388_608), in: destination) }
    }
}

extension InstanceTransfer {
    func exportComplete(_ instance: GameInstance, to destination: URL, includeWorlds: Bool, progress: @Sendable (InstallProgress) -> Void) async throws {
        guard instance.installed else { throw RuriError.message(Messages.CoreCompleteInstancePack.completeExportRequiresInstalledInstance) }
        let sourceGame = paths.game(instance.id)
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let protected = [sourceGame, paths.instance(instance.id), try paths.resources(for: instance).root]
        guard !protected.contains(where: { destinationPath == $0.standardizedFileURL.resolvingSymlinksInPath().path || destinationPath.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/") }) else {
            throw RuriError.message(Messages.CoreCompleteInstancePack.completeExportLocationInvalid)
        }
        try paths.prepare()
        let workspace = paths.cache.appendingPathComponent("complete-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        progress(.init(Messages.CoreCompleteInstancePack.readingCompleteInstallation))
        let copy = PreparedMinecraftInstallation.portableCopy(instance)
        let plan = try MinecraftInstallationCopy.read(instance: instance, copy: copy, paths: paths, portable: true)
        var settings = instance; settings.packLibraries = nil
        func rewrite(_ arguments: String) throws -> String {
            let tokens = try ArgumentTokenizer.split(arguments)
            let replaced = tokens.map { MinecraftInstallationCopy.rewrite($0, replacements: plan.replacements) }
            return replaced == tokens ? arguments : ArgumentTokenizer.join(replaced)
        }
        settings.extraJVMArguments = try rewrite(settings.extraJVMArguments)
        settings.extraGameArguments = try settings.extraGameArguments.map(rewrite)
        settings.javaPath = nil; settings.launchOverrides = nil
        var components = instance.repositoryComponents ?? instance.importedInstallation?.components ?? []
        if components.isEmpty, instance.loader != .vanilla, let version = instance.loaderVersion { components = [.init(name: instance.loader.title, version: version)] }
        let installation = ImportedMinecraftInstallation(sourceVersionID: instance.repositoryVersionID ?? instance.importedInstallation?.sourceVersionID ?? instance.gameVersion, components: components)
        try installation.validate()
        let pack = try ModpackRegistry.load(paths: paths, instanceID: instance.id)
        let declared = Set((pack?.files ?? []).compactMap { $0.path.split(separator: "/").first.map(String.init) })
        var excluded = try Self.exclusions(sourceGame, includeWorlds: includeWorlds).subtracting(declared)
        excluded.formUnion(MinecraftGameDataFiles.reservedNames(paths: paths, instanceID: instance.id)); excluded.insert(".ruri")
        if !includeWorlds { excluded.insert("saves") }
        let entries = try FileTree.entries(in: sourceGame, excluding: excluded)
        let game = workspace.appendingPathComponent("minecraft")
        let receipt = try FileTreeManifest.capture(entries)
        try RunDirectoryFileCopy.entries(entries, to: game, validate: { try paths.validateInstanceLocation(instance.id) }) { _, _ in }
        try receipt.requireMatch(in: game, ignoringTransientFiles: true)
        let resourceRoot = workspace.appendingPathComponent("installation")
        try await plan.write(resourceRoot: resourceRoot, clientFile: resourceRoot.appendingPathComponent("versions/game/game.jar"),
                             manifestFile: resourceRoot.appendingPathComponent("version.json"), metadata: resourceRoot, progress: progress)
        try MinecraftInstallationCopy.retainOriginals(from: paths.instance(instance.id), to: resourceRoot)
        guard try MinecraftInstallationCopy.read(instance: instance, copy: copy, paths: paths, portable: true) == plan else { throw RuriError.message(Messages.CoreCompleteInstancePack.installationFilesChangedDuringExport) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(PortableInstance(settings, installation: installation)).write(to: workspace.appendingPathComponent("ruri-instance.json"))
        try encoder.encode(await ContentManager(paths: paths, instanceID: instance.id).records()).write(to: workspace.appendingPathComponent("ruri-content.json"))
        if let pack {
            try encoder.encode(pack).write(to: workspace.appendingPathComponent("ruri-modpack-state.json"))
        }
        let source = paths.instance(instance.id).appendingPathComponent("source-mcbbs.packmeta")
        if FileManager.default.fileExists(atPath: source.path) { try Self.read(source).write(to: workspace.appendingPathComponent("ruri-source-mcbbs.packmeta")) }
        progress(.init(Messages.CoreCompleteInstancePack.compressingCompleteCopy))
        try SafeArchive.create(from: workspace, to: destination) { done, total in progress(.init(Messages.CoreCompleteInstancePack.compressingCompleteCopy, completed: done, total: total)) }
    }
}
