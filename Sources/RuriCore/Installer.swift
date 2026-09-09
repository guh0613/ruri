import Foundation

public actor GameInstaller {
    public static let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
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
        let base = loader == .fabric ? "https://meta.fabricmc.net/v2/versions/loader" : "https://meta.quiltmc.org/v3/versions/loader"
        return try await HTTPClient.shared.get([Entry].self, from: URL(string: base)!.appendingPathComponent(game)).map(\.loader.version)
    }
    public func install(_ input: GameInstance, concurrency: Int = 8, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> GameInstance {
        try paths.prepare()
        await progress(InstallProgress("正在获取版本清单"))
        let catalog = try await catalog()
        guard let version = catalog.versions.first(where: { $0.id == input.gameVersion }) else { throw RuriError.message("找不到 Minecraft \(input.gameVersion)") }
        let baseFile = try LauncherPaths.safePath("\(version.id)/\(version.id).json", within: paths.versions)
        try await downloader.fetch(DownloadItem(url: version.url, destination: baseFile, sha1: version.sha1))
        var manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: baseFile))
        var instance = input
        if instance.loader != .vanilla {
            await progress(InstallProgress("正在安装 \(instance.loader.title)"))
            if instance.loaderVersion == nil { instance.loaderVersion = try await loaderVersions(instance.loader, game: instance.gameVersion).first }
            guard let loaderVersion = instance.loaderVersion else { throw RuriError.message("此版本没有可用的 \(instance.loader.title) 加载器。") }
            let base = instance.loader == .fabric ? "https://meta.fabricmc.net/v2/versions/loader" : "https://meta.quiltmc.org/v3/versions/loader"
            let url = URL(string: base)!.appendingPathComponent(instance.gameVersion).appendingPathComponent(loaderVersion).appendingPathComponent("profile/json")
            let child = try await HTTPClient.shared.get(VersionManifest.self, from: url)
            manifest = manifest.merging(child: child)
        }
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        try await prepareFiles(manifest, instance: instance, concurrency: concurrency, progress: progress)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: paths.manifest(instance.id), options: .atomic)
        instance.installed = true
        await progress(InstallProgress("安装完成", completed: 1, total: 1))
        return instance
    }
    public func repair(_ instance: GameInstance, concurrency: Int = 8, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let manifest = try loadManifest(instance)
        try await prepareFiles(manifest, instance: instance, concurrency: concurrency, progress: progress)
    }
    public func loadManifest(_ instance: GameInstance) throws -> VersionManifest {
        try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: paths.manifest(instance.id)))
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
        let arch = Self.architecture(for: manifest)
        guard let client = manifest.downloads?["client"] else { throw RuriError.message("版本清单缺少客户端文件") }
        let jarID = manifest.jar ?? instance.gameVersion
        let clientFile = try LauncherPaths.safePath("\(jarID)/\(jarID).jar", within: paths.versions)
        var files = [DownloadItem(client, to: clientFile)]
        var nativeFiles: [(URL, [String])] = []
        for library in manifest.libraries where Self.allowed(library, architecture: arch) {
            if let artifact = try library.artifact() {
                let target = try LauncherPaths.safePath(artifact.path ?? Library.mavenPath(library.name), within: paths.libraries)
                files.append(DownloadItem(artifact, to: target))
            }
            if let artifact = library.nativeArtifact(architecture: arch) {
                let target = try LauncherPaths.safePath(artifact.path ?? "natives/\(artifact.url.lastPathComponent)", within: paths.libraries)
                files.append(DownloadItem(artifact, to: target)); nativeFiles.append((target, library.extract?.exclude ?? ["META-INF/"]))
            }
        }
        if let logging = manifest.logging?.client {
            let target = try LauncherPaths.safePath("log_configs/\(logging.file.id)", within: paths.assets)
            files.append(DownloadItem(url: logging.file.url, destination: target, sha1: logging.file.sha1, size: logging.file.size))
        }
        await progress(InstallProgress("正在下载游戏与依赖库", total: files.count))
        try await downloader.download(files, concurrency: concurrency) { done, total in await progress(InstallProgress("正在下载游戏与依赖库", completed: done, total: total)) }
        if let index = manifest.assetIndex {
            let indexFile = try LauncherPaths.safePath("indexes/\(index.id).json", within: paths.assets)
            try await downloader.fetch(DownloadItem(url: index.url, destination: indexFile, sha1: index.sha1, size: index.size))
            let assets = try JSONDecoder().decode(AssetObjects.self, from: Data(contentsOf: indexFile))
            let objects = try assets.objects.values.map { object -> DownloadItem in
                guard object.hash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw RuriError.message("资源索引包含无效哈希") }
                let subpath = "\(object.hash.prefix(2))/\(object.hash)"
                return DownloadItem(url: URL(string: "https://resources.download.minecraft.net/\(subpath)")!, destination: try LauncherPaths.safePath("objects/\(subpath)", within: paths.assets), sha1: object.hash, size: object.size)
            }
            try await downloader.download(objects, concurrency: concurrency) { done, total in await progress(InstallProgress("正在下载游戏资源", completed: done, total: total)) }
            if assets.virtual == true || assets.map_to_resources == true {
                let root = assets.map_to_resources == true ? paths.game(instance.id).appendingPathComponent("resources") : try LauncherPaths.safePath("virtual/\(index.id)", within: paths.assets)
                for (name, object) in assets.objects {
                    let target = try LauncherPaths.safePath(name, within: root)
                    let source = paths.assets.appendingPathComponent("objects/\(object.hash.prefix(2))/\(object.hash)")
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
                }
            }
        }
        await progress(InstallProgress("正在准备 macOS 原生库"))
        let natives = paths.instance(instance.id).appendingPathComponent("natives")
        try FileManager.default.createDirectory(at: natives, withIntermediateDirectories: true)
        for (file, excluded) in nativeFiles { try SafeArchive.extract(file, to: natives, excluding: excluded) }
    }
}
