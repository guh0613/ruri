import RuriLocalization
import Foundation
import ZIPFoundation
import CryptoKit

public enum ForgeCatalog {
    public static func versions(loader: LoaderKind, game: String, client: HTTPClient = .shared) async throws -> [String] {
        let data = try await client.data(from: LoaderEndpoints.mavenMetadata(loader: loader, game: game))
        let parser = XMLParser(data: data); let delegate = MavenVersionsParser(); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw RuriError.message(Messages.CoreForgeInstaller.loaderVersionsReadFailed) }
        let candidates: [String]
        if loader == .forge || game == "1.20.1" {
            candidates = delegate.versions.filter { $0.hasPrefix(game + "-") }.map { String($0.dropFirst(game.count + 1)) }
        } else {
            guard let prefix = neoForgePrefix(game) else { return [] }
            candidates = delegate.versions.filter { $0.hasPrefix(prefix) }
        }
        return LoaderRelease.sorted(candidates.map { LoaderRelease(version: $0) }).map(\.version)
    }
    public static func neoForgePrefix(_ game: String) -> String? {
        let parts = game.split(separator: ".").map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        if parts[0] == "1" { return "\(parts[1]).\(parts.count > 2 ? parts[2] : "0")." }
        return "\(parts[0]).\(parts[1]).\(parts.count > 2 ? parts[2] : "0")."
    }
    public static func repository(loader: LoaderKind, game: String) -> URL {
        LoaderEndpoints.repository(loader: loader, game: game)
    }
    public static func installerURL(loader: LoaderKind, game: String, version: String) throws -> URL {
        try LoaderEndpoints.installer(loader: loader, game: game, version: version)
    }
}
private final class MavenVersionsParser: NSObject, XMLParserDelegate {
    var versions: [String] = []; private var inVersion = false; private var text = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) { if elementName == "version" { inVersion = true; text = "" } }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inVersion { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "version" { versions.append(text.trimmingCharacters(in: .whitespacesAndNewlines)); inVersion = false }
    }
}

public actor ForgeInstaller {
    private let paths: LauncherPaths
    private let downloader: DownloadManager
    private let protectExistingFiles: Bool
    public init(paths: LauncherPaths, downloader: DownloadManager, protectExistingFiles: Bool = false) {
        self.paths = paths; self.downloader = downloader; self.protectExistingFiles = protectExistingFiles
    }
    private struct Profile: Decodable {
        let minecraft: String?
        let json: String?
        let version: String?
        let libraries: [Library]?
        let versionInfo: VersionManifest?
        struct Processor: Decodable { let jar: String; let classpath: [String]?; let sides: [String]? }
        let processors: [Processor]?
        struct Legacy: Decodable { let minecraft: String?; let path: String?; let filePath: String? }
        let install: Legacy?
    }
    public func install(instance: GameInstance, base: VersionManifest, concurrency: Int, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> VersionManifest {
        let resources = try paths.resources(for: instance)
        guard let version = instance.loaderVersion else { throw RuriError.message(Messages.CoreForgeInstaller.loaderVersionRequired) }
        let url = try ForgeCatalog.installerURL(loader: instance.loader, game: instance.gameVersion, version: version)
        let checksumData = try await HTTPClient.shared.data(from: LoaderEndpoints.installerChecksum(url))
        let checksum = String(decoding: checksumData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first ?? ""
        guard checksum.range(of: "^[0-9A-Fa-f]{40}$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreForgeInstaller.installerChecksumMissing) }
        let jar = try LauncherPaths.safePath("installers/\(instance.loader.rawValue)-\(instance.gameVersion)-\(version).jar", within: paths.cache)
        await progress(InstallProgress(Messages.CoreForgeInstaller.downloadInstaller(instance.loader.title)))
        try await downloader.fetch(DownloadItem(url: url, destination: jar, sha1: checksum))
        let archive = try Archive(url: jar, accessMode: .read)
        let profile = try JSONDecoder().decode(Profile.self, from: read("install_profile.json", in: archive))
        guard (profile.minecraft ?? profile.install?.minecraft ?? profile.versionInfo?.inheritsFrom) == instance.gameVersion else { throw RuriError.message(Messages.CoreForgeInstaller.minecraftVersionMismatch) }
        if let legacy = profile.versionInfo { return try installLegacy(legacy, profile: profile, archive: archive, resources: resources) }
        guard let json = profile.json else { throw RuriError.message(Messages.CoreForgeInstaller.versionManifestMissing) }
        let child = try JSONDecoder().decode(VersionManifest.self, from: read(json, in: archive))
        guard child.inheritsFrom == instance.gameVersion else { throw RuriError.message(Messages.CoreForgeInstaller.parentVersionMismatch) }
        let work = try LauncherPaths.safePath("loader-work/\(instance.id.uuidString)/\(instance.loader.rawValue)-\(version)", within: paths.cache)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let jarID = instance.repositoryVersionID ?? instance.gameVersion
        let sourceJar = try paths.clientJar(jarID, instance: instance)
        guard let client = base.downloads?["client"] else { throw RuriError.message(Messages.CoreForgeInstaller.vanillaClientMissing) }
        try await downloader.fetch(DownloadItem(client, to: sourceJar))
        let vanilla = try LauncherPaths.safePath("versions/\(instance.gameVersion)", within: work)
        try FileManager.default.createDirectory(at: vanilla, withIntermediateDirectories: true)
        try copyAtomically(sourceJar, to: vanilla.appendingPathComponent("\(instance.gameVersion).jar"))
        try JSONEncoder().encode(base).write(to: vanilla.appendingPathComponent("\(instance.gameVersion).json"), options: .atomic)
        try Data("{\"profiles\":{}}".utf8).write(to: work.appendingPathComponent("launcher_profiles.json"), options: .atomic)
        let libraries = (profile.libraries ?? []) + child.libraries
        let workLibraries = work.appendingPathComponent("libraries")
        var requests: [DownloadItem] = []; var seen = Set<String>()
        for library in libraries {
            guard let artifact = try library.artifact() else { continue }
            let relative = try artifact.path ?? Library.mavenPath(library.name)
            guard seen.insert(relative).inserted else { continue }
            let target = try LauncherPaths.safePath(relative, within: workLibraries)
            let cached = try LauncherPaths.safePath(relative, within: resources.libraries)
            if DownloadManager.valid(cached, item: DownloadItem(artifact, to: cached)) { try copyAtomically(cached, to: target) }
            else if let entry = archive["maven/" + relative], entry.type == .file {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                let crc = try archive.extract(entry, to: target)
                guard crc == entry.checksum else { throw RuriError.message(Messages.CoreForgeInstaller.embeddedFileChecksumFailed(String(describing: relative))) }
            } else if artifact.url?.scheme == "https" { requests.append(DownloadItem(artifact, to: target)) }
        }
        try await downloader.download(requests, concurrency: concurrency) { done, total in await progress(InstallProgress(Messages.CoreForgeInstaller.prepareDependencies, completed: done, total: total)) }
        let processorCoordinates = (profile.processors ?? []).filter { $0.sides == nil || $0.sides!.contains("client") }
            .flatMap { [$0.jar] + ($0.classpath ?? []) }
        let processorFiles = try processorCoordinates.map { try LauncherPaths.safePath(Library.mavenPath($0), within: workLibraries) }
        let minimumJava = try JavaBytecode.minimumMajor(in: [jar] + processorFiles)
        let java = try await InstallerJavaRuntime.resolve(minimumMajor: minimumJava, component: instance.loader.title, paths: paths)
        await progress(InstallProgress(Messages.CoreForgeInstaller.runInstaller(instance.loader.title)))
        let runner = InstallerProcess()
        let log = paths.instance(instance.id).appendingPathComponent("installer.log")
        let status = try await runner.run(java: java, arguments: ["-Djava.awt.headless=true", "-jar", jar.path, "--installClient", work.path], directory: work, logURL: log, runtimePaths: paths) { line in await progress(InstallProgress(line)) }
        guard status == 0 else {
            let tail = await runner.lastOutput()
            throw RuriError.message(Messages.CoreForgeInstaller.installerExited(instance.loader.title, String(describing: status), log.path, String(describing: String(tail.suffix(1200)))))
        }
        let installedJSON = try LauncherPaths.safePath("versions/\(child.id)/\(child.id).json", within: work)
        var installed = try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: installedJSON))
        guard installed.id == child.id, installed.inheritsFrom == instance.gameVersion else { throw RuriError.message(Messages.CoreForgeInstaller.generatedManifestMismatch) }
        // First validate declared artifacts against the official hashes. Shared
        // cache paths are never given to the external installation process.
        for library in libraries {
            guard let artifact = try library.artifact() else { continue }
            let relative = try artifact.path ?? Library.mavenPath(library.name)
            let source = try LauncherPaths.safePath(relative, within: workLibraries)
            if !FileManager.default.fileExists(atPath: source.path) { continue }
            guard DownloadManager.valid(source, item: DownloadItem(artifact, to: source)) else { throw RuriError.message(Messages.CoreForgeInstaller.generatedFileChecksumFailed(String(describing: relative))) }
            let target = try LauncherPaths.safePath(relative, within: resources.libraries)
            if !DownloadManager.valid(target, item: DownloadItem(artifact, to: target)) { try copyAtomically(source, to: target) }
        }
        // NeoForge locates patched client jars and mappings dynamically; those
        // processor outputs are absent from the launcher classpath manifest.
        // Preserve and fingerprint them separately, without adding them to -cp.
        await progress(InstallProgress(Messages.CoreForgeInstaller.verifyGeneratedFiles))
        var generated: [Artifact] = []
        if let enumerator = FileManager.default.enumerator(at: workLibraries, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) {
            while let file = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { throw RuriError.message(Messages.CoreForgeInstaller.unsupportedSymlink) }
                guard values.isRegularFile == true else { continue }
                let relative = String(file.path.dropFirst(workLibraries.path.count + 1))
                guard !seen.contains(relative) else { continue }
                if ["jar", "zip"].contains(file.pathExtension) { try SafeArchive.verify(file) }
                let handle = try FileHandle(forReadingFrom: file); var hash = Insecure.SHA1()
                do { while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }; try handle.close() }
                catch { try? handle.close(); throw error }
                let artifact = Artifact(path: relative, url: nil, sha1: hash.finalize().map { String(format: "%02x", $0) }.joined(), size: Int64(values.fileSize ?? 0))
                let target = try LauncherPaths.safePath(relative, within: resources.libraries)
                if !DownloadManager.valid(target, item: DownloadItem(artifact, to: target)) { try copyAtomically(file, to: target) }
                generated.append(artifact)
            }
        }
        installed.generatedLibraries = generated
        try? FileManager.default.removeItem(at: work)
        return installed
    }
    private func read(_ path: String, in archive: Archive) throws -> Data {
        let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let entry = archive[name], entry.type == .file, entry.uncompressedSize < 8 * 1024 * 1024 else { throw RuriError.message(Messages.CoreForgeInstaller.embeddedFileMissing(name)) }
        var data = Data(); let crc = try archive.extract(entry) { data.append($0) }
        guard crc == entry.checksum else { throw RuriError.message(Messages.CoreForgeInstaller.manifestChecksumFailed) }; return data
    }
    private func installLegacy(_ child: VersionManifest, profile: Profile, archive: Archive, resources: GameResourcePaths) throws -> VersionManifest {
        guard let coordinate = profile.install?.path, let filename = profile.install?.filePath,
              let entry = archive[filename], entry.type == .file else { throw RuriError.message(Messages.CoreForgeInstaller.legacyClientMissing) }
        let target = try LauncherPaths.safePath(Library.mavenPath(coordinate), within: resources.libraries)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).jar")
        defer { try? FileManager.default.removeItem(at: staging) }
        let crc = try archive.extract(entry, to: staging)
        guard crc == entry.checksum else { throw RuriError.message(Messages.CoreForgeInstaller.legacyFileChecksumFailed) }
        try copyAtomically(staging, to: target)
        return child
    }
    private func copyAtomically(_ source: URL, to target: URL) throws {
        if protectExistingFiles, FileManager.default.fileExists(atPath: target.path) {
            guard try InstanceTransfer.sha1(source) == InstanceTransfer.sha1(target) else {
                throw RuriError.message(Messages.CoreForgeInstaller.dependencyReplacementRequired(target.lastPathComponent))
            }
            return
        }
        if let id = paths.repositoryImportID,
           target.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(paths.directoryRoot(paths.directoryID(for: id)).standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("libraries").path + "/"),
           FileManager.default.fileExists(atPath: target.path) {
            guard try InstanceTransfer.sha1(source) == InstanceTransfer.sha1(target) else {
                throw RuriError.message(Messages.CoreForgeInstaller.dependencyConflict(target.path))
            }
            return
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        guard rename(staging.path, target.path) == 0 else { throw RuriError.message(Messages.CoreForgeInstaller.loaderFileSaveFailed(target.lastPathComponent)) }
    }
}
