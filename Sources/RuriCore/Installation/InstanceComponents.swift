import Foundation

public struct ComponentBackup: Codable, Sendable {
    public let createdAt: Date
    public let instance: GameInstance
    let manifest: Data
    let resourceRoot: URL
    public var title: String { instance.loader.title + (instance.loaderVersion.map { " " + $0 } ?? "") }
}

/// Prepare dependencies before atomically replacing the active launch manifest.
/// Game data and the original client JAR are never part of the replacement.
public actor InstanceComponents {
    private let paths: LauncherPaths
    private let downloader: DownloadManager
    public init(paths: LauncherPaths, downloader: DownloadManager = DownloadManager()) {
        self.paths = paths; self.downloader = downloader
    }

    public nonisolated static func unavailableReason(_ instance: GameInstance) -> String? {
        guard instance.installed else { return "请先完成此实例的安装。" }
        if let issue = instance.repositoryIssue { return issue }
        let supported = Set(LoaderKind.allCases.map(\.title))
        let additional = (instance.repositoryComponents ?? instance.importedInstallation?.components ?? []).filter { !supported.contains($0.name) }
        if !additional.isEmpty { return "此实例还有 " + additional.map(\.name).joined(separator: "、") + "，暂不支持保留这些组件的更换操作。" }
        if (instance.repositoryComponents ?? instance.importedInstallation?.components ?? []).filter({ supported.contains($0.name) }).count > 1 {
            return "此实例同时使用多个加载器，暂不支持保留组合的更换操作。"
        }
        return nil
    }

    public func backup(for id: UUID) throws -> ComponentBackup? {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        let file = try backupFile(id, paths: current)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(ComponentBackup.self, from: RunDirectoryCopyGuard.read(file, limit: 48 * 1024 * 1024))
    }

    public func change(_ requested: GameInstance, to loader: LoaderKind, version: String?, concurrency: Int = 8,
                       progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> PersistentState {
        let downloader = downloader
        return try await change(requested, to: loader, version: version, installing: { candidate, location in
            try await GameInstaller(paths: location, downloader: downloader, protectExistingFiles: true)
                .install(candidate, concurrency: concurrency, progress: progress)
        }, progress: progress)
    }

    func change(_ requested: GameInstance, to loader: LoaderKind, version: String?,
                installing: @Sendable (GameInstance, LauncherPaths) async throws -> GameInstance,
                progress: @Sendable @escaping (InstallProgress) async -> Void = { _ in }) async throws -> PersistentState {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        let original = try find(requested.id, state: state)
        _ = try original.applyingInstallation(requested, requested: requested)
        if let reason = Self.unavailableReason(original) { throw RuriError.message(reason) }
        guard loader == .vanilla || version?.isEmpty == false else { throw RuriError.message("请选择加载器版本。") }
        guard loader != original.loader || (loader != .vanilla && version != original.loaderVersion) else { throw RuriError.message("当前已经使用这个加载器版本。") }
        let lease = try GameRunLease.acquire(paths: current, instanceID: original.id)
        defer { withExtendedLifetime(lease) {} }
        try current.validateBinding(original)
        let documents = try sourceDocuments(original, paths: current)
        let previous = try RunDirectoryCopyGuard.read(current.manifest(original.id), limit: 32 * 1024 * 1024)
        let active = try await GameInstaller(paths: current).loadManifest(original)
        let resources = try current.resources(for: original)
        let clientID = active.jar ?? original.gameVersion
        let client = try current.clientJar(clientID, instance: original)
        guard FileManager.default.fileExists(atPath: client.path) else { throw RuriError.message("游戏客户端缺失，请先修复此实例。") }
        let work = try LauncherPaths.safePath("component-work/" + UUID().uuidString, within: current.instance(original.id))
        let staging = LauncherPaths(root: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        // Share existing download caches, protecting every existing dependency.
        // Only the temporary client and launch manifest are replaced by install.
        for (name, destination) in [("libraries", resources.libraries), ("assets", resources.assets), ("cache", paths.cache), ("runtimes", paths.runtimes)] {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: work.appendingPathComponent(name), withDestinationURL: destination)
        }
        var candidate = GameInstance(name: original.name, gameVersion: original.gameVersion, loader: loader, loaderVersion: loader == .vanilla ? nil : version)
        candidate.packLibraries = original.packLibraries?.filter { !Self.isLoaderLibrary($0) }
        defer {
            let log = staging.instance(candidate.id).appendingPathComponent("installer.log")
            if let data = try? RunDirectoryCopyGuard.read(log, limit: 8 * 1024 * 1024) {
                try? data.write(to: current.instance(original.id).appendingPathComponent("component-installer.log"), options: .atomic)
            }
        }
        let stagedClient = try staging.clientJar(original.gameVersion, instance: candidate)
        try FileManager.default.createDirectory(at: stagedClient.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: client, to: stagedClient)
        let installed = try await installing(candidate, staging)
        var manifest = try await GameInstaller(paths: staging).loadManifest(installed)
        manifest.id = original.repositoryVersionID ?? manifest.id
        manifest.jar = clientID; manifest.inheritsFrom = nil
        manifest.downloads?["client"] = active.downloads?["client"]
        let replacements = [staging.libraries.path: "${library_directory}", staging.assets.path: "${assets_root}",
                            staging.game(candidate.id).path: "${game_directory}", staging.instance(candidate.id).appendingPathComponent("natives").path: "${natives_directory}",
                            stagedClient.path: client.path, stagedClient.deletingLastPathComponent().path: client.deletingLastPathComponent().path]
        func rewrite(_ value: String) throws -> String {
            let result = MinecraftInstallationCopy.rewrite(value, replacements: replacements)
            guard !result.contains(work.path) else { throw RuriError.message("加载器生成了不能迁移的临时路径，原配置已保留。") }
            return result
        }
        func argument(_ value: LaunchArgument) throws -> LaunchArgument {
            switch value { case .text(let value): .text(try rewrite(value)); case .conditional(let rules, let values): .conditional(rules, try values.map(rewrite)) }
        }
        if var arguments = manifest.arguments {
            arguments.game = try arguments.game?.map(argument); arguments.jvm = try arguments.jvm?.map(argument); manifest.arguments = arguments
        }
        if let legacy = manifest.minecraftArguments { manifest.minecraftArguments = try ArgumentTokenizer.join(ArgumentTokenizer.split(legacy).map(rewrite)) }
        let components: [MinecraftDirectoryComponent] = loader == .vanilla ? [] : [.init(name: loader.title, version: installed.loaderVersion ?? version!)]
        let encoded = try encode(manifest, gameVersion: original.gameVersion, components: components)
        var replacement = original
        replacement.loader = loader; replacement.loaderVersion = loader == .vanilla ? nil : installed.loaderVersion
        replacement.packLibraries = candidate.packLibraries
        if original.repositoryVersionID != nil { replacement.repositoryComponents = components }
        if let imported = original.importedInstallation {
            replacement.importedInstallation = .init(sourceVersionID: imported.sourceVersionID, components: components)
        }
        try Task.checkCancellation()
        await progress(InstallProgress("正在应用加载器设置"))
        let backup = ComponentBackup(createdAt: Date(), instance: original, manifest: previous, resourceRoot: resources.root)
        return try publish(replacement, requested: original, manifest: encoded, previous: previous, documents: documents, backup: backup, paths: current)
    }

    public func restore(_ requested: GameInstance) throws -> PersistentState {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        let original = try find(requested.id, state: state)
        _ = try original.applyingInstallation(requested, requested: requested)
        let lease = try GameRunLease.acquire(paths: current, instanceID: original.id)
        defer { withExtendedLifetime(lease) {} }
        guard let backup = try backup(for: original.id), backup.instance.id == original.id,
              backup.instance.gameVersion == original.gameVersion,
              backup.resourceRoot == (try current.resources(for: original)).root else { throw RuriError.message("没有适用于当前位置的加载器备份。") }
        let documents = try sourceDocuments(original, paths: current)
        let previous = try RunDirectoryCopyGuard.read(current.manifest(original.id), limit: 32 * 1024 * 1024)
        let reverse = ComponentBackup(createdAt: Date(), instance: original, manifest: previous, resourceRoot: backup.resourceRoot)
        var restored = original
        restored.loader = backup.instance.loader; restored.loaderVersion = backup.instance.loaderVersion
        restored.repositoryComponents = backup.instance.repositoryComponents; restored.importedInstallation = backup.instance.importedInstallation
        restored.packLibraries = backup.instance.packLibraries
        return try publish(restored, requested: original, manifest: backup.manifest, previous: previous, documents: documents, backup: reverse, paths: current)
    }

    private func publish(_ replacement: GameInstance, requested: GameInstance, manifest: Data, previous: Data,
                         documents: [MinecraftDirectoryDocument], backup: ComponentBackup, paths current: LauncherPaths) throws -> PersistentState {
        let file = current.manifest(requested.id)
        var published = false
        do {
            return try StateStore.update(paths) { latest in
                let original = try find(requested.id, state: latest)
                var updated = try original.applyingInstallation(requested, requested: requested)
                try current.validateBinding(original)
                guard original.importedInstallation == requested.importedInstallation else { throw RuriError.message("实例组件在操作期间改变，请重新打开组件管理。") }
                for document in documents {
                    let actual = FileManager.default.fileExists(atPath: document.url.path) ? try RunDirectoryCopyGuard.read(document.url, limit: 32 * 1024 * 1024) : nil
                    guard actual == document.data else { throw RuriError.message("原版本文件在准备期间改变，请重新尝试。") }
                }
                guard try RunDirectoryCopyGuard.read(file, limit: 32 * 1024 * 1024) == previous else { throw RuriError.message("启动清单已改变，请重新尝试。") }
                updated.loader = replacement.loader; updated.loaderVersion = replacement.loaderVersion
                updated.repositoryComponents = replacement.repositoryComponents; updated.importedInstallation = replacement.importedInstallation
                updated.packLibraries = replacement.packLibraries
                try JSONEncoder().encode(backup).write(to: backupFile(requested.id, paths: current), options: .atomic)
                try manifest.write(to: file, options: .atomic); published = true
                latest.instances[latest.instances.firstIndex(where: { $0.id == updated.id })!] = updated
            }
        } catch {
            if published {
                do { try previous.write(to: file, options: .atomic) }
                catch { throw RuriError.message("加载器设置未完成保存，请在组件管理中恢复上次配置。") }
            }
            throw error
        }
    }

    private func sourceDocuments(_ instance: GameInstance, paths: LauncherPaths) throws -> [MinecraftDirectoryDocument] {
        guard let versionID = instance.repositoryVersionID else { return [] }
        let catalog = try MinecraftDirectoryReader().scanNow(paths.directoryRoot(paths.directoryID(for: instance.id)))
        guard let version = catalog.versions.first(where: { $0.id == versionID }), version.issue == nil else { throw RuriError.message("当前版本的启动清单不可用，请先修复。") }
        if let dependent = catalog.versions.first(where: { $0.id != versionID && $0.documents.contains(where: { $0.url == paths.manifest(instance.id) }) }) {
            throw RuriError.message("“\(dependent.id)”继承此版本，直接更换会同时影响它。请先为此实例创建独立副本。")
        }
        return version.documents
    }
    private func find(_ id: UUID, state: PersistentState) throws -> GameInstance {
        guard let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message("实例已从列表移除。") }
        return instance
    }
    private func backupFile(_ id: UUID, paths: LauncherPaths) throws -> URL { try LauncherPaths.safePath("previous-components.json", within: paths.instance(id)) }
    private static func isLoaderLibrary(_ library: Library) -> Bool {
        ["net.fabricmc:", "net.legacyfabric:", "com.mumfrey:liteloader:", "org.quiltmc:", "net.minecraftforge:", "net.neoforged:", "cpw.mods:", "optifine:", "net.optifine:"].contains { library.name.hasPrefix($0) }
            || library.name.hasPrefix("org.lwjgl.lwjgl:") && library.name.contains("+legacyfabric.")
    }
    private func encode(_ manifest: VersionManifest, gameVersion: String, components: [MinecraftDirectoryComponent]) throws -> Data {
        var document = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as! [String: Any]
        document["clientVersion"] = gameVersion
        document["patches"] = components.map { ["id": $0.name.lowercased(), "version": $0.version] }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
    }
}
