import RuriLocalization
import Foundation
import Darwin

public struct RemoteJava: Identifiable, Codable, Sendable {
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
        try paths.prepare()
        let cache = try LauncherPaths.safePath("java-runtime-descriptors", within: paths.cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for runtime in result { try JSONEncoder().encode(runtime).write(to: LauncherPaths.safePath(runtime.id + ".json", within: cache), options: .atomic) }
        return result.sorted { $0.architecture != $1.architecture ? $0.architecture == JavaRuntime.hostArchitecture : $0.major > $1.major }
    }
    public func install(_ runtime: RemoteJava, downloader: DownloadManager, repairing: Bool = false, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> JavaRuntime {
        struct Manifest: Decodable, Sendable {
            struct File: Decodable, Sendable { let type: String; let downloads: [String: Artifact]?; let executable: Bool?; let target: String? }
            let files: [String: File]
        }
        try paths.prepare()
        let destination = try JavaRuntimeStore.directory(runtime.id, paths: paths)
        let binary = destination.appendingPathComponent("jre.bundle/Contents/Home/bin/java")
        if !repairing, FileManager.default.fileExists(atPath: destination.path) {
            let reading = try JavaRuntimeLease.acquire(id: runtime.id, paths: paths, exclusive: false)
            defer { withExtendedLifetime(reading) {} }
            if let existing = try? JavaDiscovery.inspect(binary.path), existing.major == runtime.major, existing.architecture == runtime.architecture { return existing }
            throw RuriError.message(Messages.CoreJavaInstaller.existingText1(String(describing: destination.lastPathComponent)))
        }
        let lease = try JavaRuntimeLease.acquire(id: runtime.id, paths: paths, exclusive: true)
        defer { withExtendedLifetime(lease) {} }
        try JavaRuntimeLease.requireNoRunningProcess(in: destination)
        if repairing, try StateStore.load(paths).schemaVersion < 17 { try StateStore.update(paths) { _ in } }
        let replacing = FileManager.default.fileExists(atPath: destination.path)
        guard repairing || !replacing else { throw RuriError.message(Messages.CoreJavaInstaller.replacingText1) }
        let manifestURL = try LauncherPaths.safePath("java-\(runtime.id).json", within: paths.cache)
        await progress(InstallProgress(Messages.CoreJavaInstaller.manifestURLText1(String(describing: runtime.major))))
        try await downloader.fetch(DownloadItem(runtime.manifest, to: manifestURL))
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let staging = try JavaRuntimeStore.directory(runtime.id, paths: paths, partial: true)
        if repairing, replacing, !FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.copyItem(at: destination, to: staging) }
        else { try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true) }
        var downloads: [DownloadItem] = []; var executables: [URL] = []; var links: [(URL, String)] = []
        for (path, file) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let target = try LauncherPaths.safePath(path, within: staging)
            switch file.type {
            case "directory": try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            case "file":
                guard let artifact = file.downloads?["raw"] else { throw RuriError.message(Messages.CoreJavaInstaller.artifactText1) }
                downloads.append(DownloadItem(artifact, to: target))
                if file.executable == true { executables.append(target) }
            case "link":
                guard let link = file.target, !link.hasPrefix("/"), !link.contains("\\") else { throw RuriError.message(Messages.CoreJavaInstaller.linkText1) }
                let resolved = target.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL
                guard resolved.path.hasPrefix(staging.standardizedFileURL.path + "/") else { throw RuriError.message(Messages.CoreJavaInstaller.resolvedText1) }
                links.append((target, link))
            default: throw RuriError.message(Messages.CoreJavaInstaller.resolvedText2(String(describing: file.type)))
            }
        }
        try await downloader.download(downloads) { done, total in await progress(InstallProgress(Messages.CoreJavaInstaller.resolvedText3(String(describing: runtime.major)), completed: done, total: total)) }
        for file in executables { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        for (target, link) in links {
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) {
                guard existing == link else { throw RuriError.message(Messages.CoreJavaInstaller.existingText2) }
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: link)
            }
            guard target.resolvingSymlinksInPath().path.hasPrefix(staging.resolvingSymlinksInPath().path + "/") else { throw RuriError.message(Messages.CoreJavaInstaller.resolvedText1) }
        }
        try Task.checkCancellation()
        let checked = try JavaDiscovery.inspect(staging.appendingPathComponent("jre.bundle/Contents/Home/bin/java").path)
        guard checked.major == runtime.major, checked.architecture == runtime.architecture else { throw RuriError.message(Messages.CoreJavaInstaller.checkedText1) }
        try JSONEncoder().encode(runtime).write(to: staging.appendingPathComponent(".ruri-runtime.json"), options: .atomic)
        if replacing {
            try JavaRuntimeLease.requireNoRunningProcess(in: destination)
            guard renamex_np(staging.path, destination.path, UInt32(RENAME_SWAP)) == 0 else { throw RuriError.message(Messages.CoreJavaInstaller.checkedText2) }
            do {
                let result = try JavaDiscovery.inspect(binary.path)
                try? FileManager.default.removeItem(at: staging)
                return result
            } catch {
                guard renamex_np(staging.path, destination.path, UInt32(RENAME_SWAP)) == 0 else { throw RuriError.message(Messages.CoreJavaInstaller.resultText1(String(describing: staging.path))) }
                throw error
            }
        }
        try FileManager.default.moveItem(at: staging, to: destination)
        return try JavaDiscovery.inspect(binary.path)
    }
}
