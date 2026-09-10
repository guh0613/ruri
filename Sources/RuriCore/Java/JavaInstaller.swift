import Foundation

public struct RemoteJava: Identifiable, Sendable {
    public var id: String { "\(component)-\(architecture)-\(version)" }
    public let component: String
    public let architecture: String
    public let version: String
    public let manifest: Artifact
    public var major: Int { component == "jre-legacy" ? 8 : Int(version.split(separator: ".").first ?? "0") ?? 0 }
    public var label: String { "Java \(major) · \(architecture == "aarch64" ? "Apple Silicon" : "Intel") · \(version)" }
}

public actor JavaInstaller {
    public static let catalogURL = MinecraftEndpoints.javaRuntimeCatalog
    private let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public func available() async throws -> [RemoteJava] {
        struct Entry: Decodable, Sendable {
            struct Version: Decodable, Sendable { let name: String }
            let manifest: Artifact; let version: Version
        }
        let catalog = try await HTTPClient.shared.get([String: [String: [Entry]]].self, from: Self.catalogURL)
        var result: [RemoteJava] = []; var seen = Set<String>()
        for (platform, arch) in [("mac-os-arm64", "aarch64"), ("mac-os", "x86_64")] {
            for (component, entries) in (catalog[platform] ?? [:]).sorted(by: { $0.key < $1.key }) {
                guard let entry = entries.first, !component.contains("snapshot") else { continue }
                let runtime = RemoteJava(component: component, architecture: arch, version: entry.version.name, manifest: entry.manifest)
                if seen.insert("\(arch)-\(runtime.major)").inserted { result.append(runtime) }
            }
        }
        return result.sorted { $0.architecture != $1.architecture ? $0.architecture == JavaRuntime.hostArchitecture : $0.major > $1.major }
    }
    public func install(_ runtime: RemoteJava, downloader: DownloadManager, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> JavaRuntime {
        struct Manifest: Decodable, Sendable {
            struct File: Decodable, Sendable { let type: String; let downloads: [String: Artifact]?; let executable: Bool?; let target: String? }
            let files: [String: File]
        }
        try paths.prepare()
        let destination = try LauncherPaths.safePath(runtime.id, within: paths.runtimes)
        let binary = destination.appendingPathComponent("jre.bundle/Contents/Home/bin/java")
        if let existing = try? JavaDiscovery.inspect(binary.path), existing.major == runtime.major, existing.architecture == runtime.architecture { return existing }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw RuriError.message("此 Java 目录已存在但无法运行，请先在 Finder 中移走：\(destination.path)") }
        let manifestURL = try LauncherPaths.safePath("java-\(runtime.id).json", within: paths.cache)
        await progress(InstallProgress("读取 Java \(runtime.major) 文件清单"))
        try await downloader.fetch(DownloadItem(runtime.manifest, to: manifestURL))
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let staging = try LauncherPaths.safePath(".partial-\(runtime.id)", within: paths.runtimes)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var downloads: [DownloadItem] = []; var executables: [URL] = []; var links: [(URL, String)] = []
        for (path, file) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let target = try LauncherPaths.safePath(path, within: staging)
            switch file.type {
            case "directory": try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            case "file":
                guard let artifact = file.downloads?["raw"] else { throw RuriError.message("Java 文件清单缺少下载信息") }
                downloads.append(DownloadItem(artifact, to: target))
                if file.executable == true { executables.append(target) }
            case "link":
                guard let link = file.target, !link.hasPrefix("/"), !link.contains("\\") else { throw RuriError.message("Java 清单包含不安全链接") }
                let resolved = target.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL
                guard resolved.path.hasPrefix(staging.standardizedFileURL.path + "/") else { throw RuriError.message("Java 链接超出运行时目录") }
                links.append((target, link))
            default: throw RuriError.message("不支持的 Java 文件类型：\(file.type)")
            }
        }
        try await downloader.download(downloads) { done, total in await progress(InstallProgress("下载 Java \(runtime.major)", completed: done, total: total)) }
        for file in executables { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        for (target, link) in links {
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) {
                guard existing == link else { throw RuriError.message("Java 目录中存在不一致的链接") }
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: link)
            }
            guard target.resolvingSymlinksInPath().path.hasPrefix(staging.resolvingSymlinksInPath().path + "/") else { throw RuriError.message("Java 链接超出运行时目录") }
        }
        try Task.checkCancellation()
        let checked = try JavaDiscovery.inspect(staging.appendingPathComponent("jre.bundle/Contents/Home/bin/java").path)
        guard checked.major == runtime.major, checked.architecture == runtime.architecture else { throw RuriError.message("下载的 Java 版本或架构不符合要求") }
        try FileManager.default.moveItem(at: staging, to: destination)
        return try JavaDiscovery.inspect(binary.path)
    }
}
