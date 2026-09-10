import Foundation

public actor GameInstaller {
    public static let manifestURL = MinecraftEndpoints.versionManifest
    public let paths: LauncherPaths
    public let downloader: DownloadManager
    public init(paths: LauncherPaths, downloader: DownloadManager = DownloadManager()) { self.paths = paths; self.downloader = downloader }
    public func catalog(force: Bool = false) async throws -> VersionCatalog {
        let cache = paths.cache.appendingPathComponent("versions.json")
        do {
            let data = try await HTTPClient.shared.data(from: Self.manifestURL)
            let result = try JSONDecoder().decode(VersionCatalog.self, from: data)
            try paths.prepare(); try data.write(to: cache, options: .atomic)
            return result
        } catch {
            if !force, let data = try? Data(contentsOf: cache), let result = try? JSONDecoder().decode(VersionCatalog.self, from: data) { return result }
            throw error
        }
    }
    public func loaderVersions(_ loader: LoaderKind, game: String) async throws -> [String] {
        struct Entry: Decodable, Sendable { struct Version: Decodable, Sendable { let version: String }; let loader: Version }
        guard loader != .vanilla else { return [] }
        if loader.usesInstaller { return try await ForgeCatalog.versions(loader: loader, game: game) }
        return try await HTTPClient.shared.get([Entry].self, from: LoaderEndpoints.versions(loader: loader, game: game)).map(\.loader.version)
    }
    public func install(_ input: GameInstance, concurrency: Int = 8, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> GameInstance {
        guard input.importedInstallation == nil else { throw RuriError.message("此实例保留了本地版本清单，请使用修复功能保留其游戏文件和组件。") }
        if input.repositoryVersionID != nil && input.installed { throw RuriError.message("此版本已存在，请使用修复功能。") }
        let location = try InstanceLocationLease.acquire(paths: paths, instanceID: input.id)
        defer { withExtendedLifetime(location) {} }
        try paths.validateBinding(input)
        try paths.prepare()
        try paths.prepareInstance(input.id)
        await progress(InstallProgress("正在获取版本清单"))
        let catalog = try await catalog()
        guard let version = catalog.versions.first(where: { $0.id == input.gameVersion }) else { throw RuriError.message("找不到 Minecraft \(input.gameVersion)") }
        let baseFile = try LauncherPaths.safePath("\(version.id)/\(version.id).json", within: paths.versions)
        try await downloader.fetch(DownloadItem(url: version.url, destination: baseFile, sha1: version.sha1))
        var manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: baseFile))
        var instance = input
        instance.directoryID = paths.directoryID(for: instance.id)
        if instance.loader != .vanilla {
            await progress(InstallProgress("正在安装 \(instance.loader.title)"))
            if instance.loaderVersion == nil { instance.loaderVersion = try await loaderVersions(instance.loader, game: instance.gameVersion).first }
            guard let loaderVersion = instance.loaderVersion else { throw RuriError.message("此版本没有可用的 \(instance.loader.title) 加载器。") }
            let child: VersionManifest
            if instance.loader.usesInstaller {
                child = try await ForgeInstaller(paths: paths, downloader: downloader).install(instance: instance, base: manifest, concurrency: concurrency, progress: progress)
            } else {
                let url = try LoaderEndpoints.profile(loader: instance.loader, game: instance.gameVersion, version: loaderVersion)
                child = try await HTTPClient.shared.get(VersionManifest.self, from: url)
            }
            manifest = manifest.merging(child: child)
        }
        if let version = instance.repositoryVersionID { manifest.id = version; manifest.jar = version; manifest.inheritsFrom = nil }
        manifest = try Self.applyingPackLibraries(instance.packLibraries ?? [], to: manifest)
        try paths.validateBinding(instance)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        try await prepareFiles(manifest, instance: instance, concurrency: concurrency, progress: progress)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try paths.validateInstanceLocation(instance.id)
        try FileManager.default.createDirectory(at: paths.manifest(instance.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: paths.manifest(instance.id), options: instance.repositoryVersionID == nil ? .atomic : .withoutOverwriting)
        instance.installed = true
        await progress(InstallProgress("安装完成", completed: 1, total: 1))
        return instance
    }
    static func applyingPackLibraries(_ libraries: [Library], to manifest: VersionManifest) throws -> VersionManifest {
        guard libraries.count <= 1000 else { throw RuriError.message("整合包依赖库数量超过限制") }
        for library in libraries {
            _ = try Library.mavenPath(library.name)
            for artifact in [try library.artifact()].compactMap({ $0 }) + Array(library.downloads?.classifiers?.values ?? [:].values) {
                if let url = artifact.url { guard ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { throw RuriError.message("整合包依赖库的下载地址无效") } }
            }
        }
        var result = manifest
        let keys = Set(libraries.map(\.identity)); var seen = Set<String>()
        result.libraries = manifest.libraries.filter { !keys.contains($0.identity) } + libraries.reversed().filter { seen.insert($0.identity).inserted }.reversed()
        return result
    }
    public func repair(_ instance: GameInstance, concurrency: Int = 8, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let location = try InstanceLocationLease.acquire(paths: paths, instanceID: instance.id)
        defer { withExtendedLifetime(location) {} }
        try paths.validateBinding(instance)
        if instance.repositoryVersionID == nil && instance.importedInstallation == nil && instance.loader.usesInstaller { _ = try await install(instance, concurrency: concurrency, progress: progress); return }
        let manifest = try loadManifest(instance)
        try await prepareFiles(manifest, instance: instance, concurrency: concurrency, progress: progress)
    }
    public func loadManifest(_ instance: GameInstance) throws -> VersionManifest {
        try paths.validateBinding(instance)
        if let versionID = instance.repositoryVersionID {
            let reader = MinecraftDirectoryReader()
            let catalog = try reader.scanNow(paths.directoryRoot(paths.directoryID(for: instance.id)))
            guard let version = catalog.versions.first(where: { $0.id == versionID }) else { throw RuriError.message("此版本已从游戏文件夹移除，请刷新实例列表。") }
            if let issue = version.issue { throw RuriError.message(issue) }
            return try reader.resolveManifestNow(version, in: catalog).selectingLibraries().repositoryManifest(root: catalog.directory)
        }
        return try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: paths.manifest(instance.id)))
    }
    /// A game directory change keeps installation resources. Legacy releases need
    /// missing mapped resources recreated in the newly selected game folder.
    public func prepareRunDirectory(_ instance: GameInstance, manifest: VersionManifest) throws {
        let location = try InstanceLocationLease.acquire(paths: paths, instanceID: instance.id)
        defer { withExtendedLifetime(location) {} }
        try paths.validateBinding(instance)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        if instance.repositoryVersionID != nil { try prepareRepositoryNatives(instance, manifest: manifest) }
        guard let index = manifest.assetIndex else { return }
        let file = try LauncherPaths.safePath("indexes/\(index.id).json", within: paths.resources(for: instance).assets)
        guard FileManager.default.fileExists(atPath: file.path) else { throw RuriError.message("游戏资源索引缺失，请先修复实例。") }
        let assets = try JSONDecoder().decode(AssetObjects.self, from: Data(contentsOf: file))
        try mapLegacyAssets(assets, indexID: index.id, instance: instance)
    }
    private func mapLegacyAssets(_ assets: AssetObjects, indexID: String, instance: GameInstance) throws {
        guard assets.virtual == true || assets.map_to_resources == true else { return }
        try paths.validateBinding(instance)
        let resourcePaths = try paths.resources(for: instance)
        let root = assets.map_to_resources == true ? paths.game(instance.id).appendingPathComponent("resources") : try LauncherPaths.safePath("virtual/\(indexID)", within: resourcePaths.assets)
        for (name, object) in assets.objects {
            try Task.checkCancellation()
            guard object.hash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw RuriError.message("资源索引包含无效哈希") }
            let target = try LauncherPaths.safePath(name, within: root)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            let source = try LauncherPaths.safePath("objects/\(object.hash.prefix(2))/\(object.hash)", within: resourcePaths.assets)
            guard DownloadManager.valid(source, item: DownloadItem(url: nil, destination: source, sha1: object.hash, size: object.size)) else { throw RuriError.message("缓存资源缺失或已损坏，请先修复实例：\(name)") }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
        }
    }
    public nonisolated static func architecture(for manifest: VersionManifest) -> String {
        // LWJGL 2 / early LWJGL 3 releases ship only Intel natives. Select matching Java.
        let hasARM = manifest.libraries.contains { $0.name.contains("natives-macos-arm64") || $0.name.contains("natives-osx-arm64") }
        return JavaRuntime.hostArchitecture == "aarch64" && hasARM ? "aarch64" : "x86_64"
    }
    public nonisolated static func allowed(_ library: Library, architecture: String) -> Bool {
        guard Rule.allows(library.rules, architecture: architecture) else { return false }
        if library.name.contains(":natives-macos") || library.name.contains(":natives-osx") {
            return library.name.contains("arm64") == (architecture == "aarch64")
        }
        return true
    }
    private func prepareFiles(_ manifest: VersionManifest, instance: GameInstance, concurrency: Int, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let resources = try paths.resources(for: instance)
        let arch = Self.architecture(for: manifest)
        guard manifest.compatibilityRules?.isEmpty != false || Rule.allows(manifest.compatibilityRules, architecture: arch) else {
            throw RuriError.message("此版本的兼容规则不支持当前 macOS 环境。")
        }
        let client = manifest.downloads?["client"] ?? Artifact(url: nil)
        let jarID = manifest.jar ?? instance.gameVersion
        let clientFile = try LauncherPaths.safePath("\(jarID)/\(jarID).jar", within: resources.versions)
        var files = [DownloadItem(client, to: clientFile)]
        for artifact in manifest.generatedLibraries ?? [] {
            guard let path = artifact.path else { throw RuriError.message("生成依赖缺少路径") }
            files.append(DownloadItem(artifact, to: try resources.libraryFile(artifact, fallback: path)))
        }
        var nativeFiles: [(URL, [String])] = []
        for library in manifest.libraries where Self.allowed(library, architecture: arch) {
            if let artifact = try library.artifact() {
                let target = try resources.libraryFile(artifact, fallback: Library.mavenPath(library.name))
                files.append(DownloadItem(artifact, to: target))
            }
            if let artifact = library.nativeArtifact(architecture: arch) {
                guard let nativePath = artifact.path ?? artifact.url.map({ "natives/\($0.lastPathComponent)" }) else { throw RuriError.message("原生库缺少文件路径") }
                let target = try resources.libraryFile(artifact, fallback: nativePath)
                files.append(DownloadItem(artifact, to: target)); nativeFiles.append((target, library.extract?.exclude ?? ["META-INF/"]))
            }
        }
        if let logging = manifest.logging?.client {
            let target = try LauncherPaths.safePath("log_configs/\(logging.file.id)", within: resources.assets)
            files.append(DownloadItem(url: logging.file.url, destination: target, sha1: logging.file.sha1, size: logging.file.size))
        }
        await progress(InstallProgress("正在下载游戏与依赖库", total: files.count))
        try await downloader.download(files, concurrency: concurrency) { done, total in await progress(InstallProgress("正在下载游戏与依赖库", completed: done, total: total)) }
        if let index = manifest.assetIndex {
            let indexFile = try LauncherPaths.safePath("indexes/\(index.id).json", within: resources.assets)
            try await downloader.fetch(DownloadItem(url: index.url, destination: indexFile, sha1: index.sha1, size: index.size))
            let assets = try JSONDecoder().decode(AssetObjects.self, from: Data(contentsOf: indexFile))
            let objects = try assets.objects.values.map { object -> DownloadItem in
                let url = try MinecraftEndpoints.asset(hash: object.hash)
                let subpath = "\(object.hash.prefix(2))/\(object.hash)"
                return DownloadItem(url: url, destination: try LauncherPaths.safePath("objects/\(subpath)", within: resources.assets), sha1: object.hash, size: object.size)
            }
            try await downloader.download(objects, concurrency: concurrency) { done, total in await progress(InstallProgress("正在下载游戏资源", completed: done, total: total)) }
            try mapLegacyAssets(assets, indexID: index.id, instance: instance)
        }
        await progress(InstallProgress("正在准备 macOS 原生库"))
        try paths.validateInstanceLocation(instance.id)
        let natives = paths.instance(instance.id).appendingPathComponent("natives")
        try FileManager.default.createDirectory(at: natives, withIntermediateDirectories: true)
        for (file, excluded) in nativeFiles { try SafeArchive.extract(file, to: natives, excluding: excluded) }
    }
}
