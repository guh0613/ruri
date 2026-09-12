import RuriLocalization
import Foundation
import ZIPFoundation

struct OptiFineInstaller: Sendable {
    let paths: LauncherPaths
    let downloader: DownloadManager
    var protectExistingFiles = false

    func install(instance: GameInstance, base: VersionManifest, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> VersionManifest {
        guard base.mainClass == "net.minecraft.client.main.Main" else { throw RuriError.message(Messages.CoreOptiFineInstaller.unsupportedStandaloneInstall) }
        guard let requested = instance.loaderVersion,
              let release = try await OptiFineCatalog.releases(game: instance.gameVersion).first(where: { $0.version == OptiFineCatalog.normalized(requested, game: instance.gameVersion) }) else {
            throw RuriError.message(Messages.CoreOptiFineInstaller.matchingOptiFineVersionMissing)
        }
        let file = try LauncherPaths.safePath("installers/optifine-\(instance.gameVersion)-\(release.version).jar", within: paths.cache)
        await progress(InstallProgress(Messages.CoreOptiFineInstaller.downloadInstallPackage))
        let url = try release.url()
        try await downloader.fetch(DownloadItem(url: url, destination: file))
        let generated = try await generate(instance: instance, base: base, installer: file, version: release.version, sourceURL: url, progress: progress)
        var child = VersionManifest(id: instance.gameVersion + "-OptiFine-" + release.version, mainClass: "net.minecraft.launchwrapper.Launch", libraries: generated.libraries)
        child.generatedLibraries = [generated.installer]
        let arguments = ["--tweakClass", "optifine.OptiFineTweaker"]
        if let legacy = base.minecraftArguments { child.minecraftArguments = try ArgumentTokenizer.join(ArgumentTokenizer.split(legacy) + arguments) }
        else { child.arguments = .init(game: arguments.map(LaunchArgument.text)) }
        return child
    }

    /// Our generated JARs use stable timestamps, so a repair can reproduce the
    /// recorded hashes without changing the launch manifest or active settings.
    func repair(instance: GameInstance, manifest: VersionManifest, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let owned = manifest.libraries.filter { $0.name.hasPrefix("optifine:OptiFine:") && $0.downloads?.artifact?.path?.contains("/ruri/") == true }
        guard !owned.isEmpty else { return }
        let resources = try paths.resources(for: instance)
        let expected = try manifest.libraries.filter { $0.name.hasPrefix("optifine:") }.compactMap { try $0.artifact() }
        let missing = try expected.contains { artifact in
            let target = try resources.libraryFile(artifact)
            return !DownloadManager.valid(target, item: DownloadItem(artifact, to: target))
        }
        guard missing else { return }
        guard let installer = manifest.generatedLibraries?.first(where: { $0.path?.hasSuffix("-installer.jar") == true && $0.path?.hasPrefix("optifine/OptiFine/") == true }),
              let version = instance.loaderVersion else { throw RuriError.message(Messages.CoreOptiFineInstaller.missingInstallSource) }
        let file = try resources.libraryFile(installer)
        try await downloader.fetch(DownloadItem(installer, to: file))
        _ = try await generate(instance: instance, base: manifest, installer: file, version: OptiFineCatalog.normalized(version, game: instance.gameVersion), sourceURL: installer.url, expected: expected, progress: progress)
    }

    private func generate(instance: GameInstance, base: VersionManifest, installer file: URL, version: String, sourceURL: URL?, expected: [Artifact]? = nil,
                          progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> (libraries: [Library], installer: Artifact) {
        let resources = try paths.resources(for: instance)
        let archive = try Archive(url: file, accessMode: .read)
        try SafeArchive.verify(file, maxBytes: 256 * 1024 * 1024)
        let metadata = try Self.metadata(archive)
        let game = ["1.8.0": "1.8", "1.9.0": "1.9"][metadata.game] ?? metadata.game
        guard game == instance.gameVersion, metadata.version == version else { throw RuriError.message(Messages.CoreOptiFineInstaller.packageVersionMismatch) }
        let coordinate = "optifine:OptiFine:\(instance.gameVersion)_\(version)"
        let relative = try Library.mavenPath(coordinate)
        let directory = (relative as NSString).deletingLastPathComponent + "/ruri/"
        let work = paths.cache.appendingPathComponent("optifine-work/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let patched = work.appendingPathComponent("patched.jar")
        if archive["optifine/Patcher.class"] != nil {
            guard let client = base.downloads?["client"] else { throw RuriError.message(Messages.CoreOptiFineInstaller.vanillaClientRequired) }
            let vanilla = work.appendingPathComponent("minecraft.jar")
            let source = try paths.clientJar(base.jar ?? instance.repositoryVersionID ?? instance.gameVersion, instance: instance)
            if DownloadManager.valid(source, item: DownloadItem(client, to: source)) { try FileManager.default.copyItem(at: source, to: vanilla) }
            else { try await downloader.fetch(DownloadItem(client, to: vanilla)) }
            var runtimes = await JavaDiscovery.scan(paths: paths)
            let major = max(8, base.requiredJava), architecture = GameInstaller.architecture(for: base)
            let java: JavaRuntime
            if let existing = try? JavaDiscovery.select(from: runtimes, major: major, architecture: architecture) { java = existing }
            else {
                let service = JavaInstaller(paths: paths)
                guard let runtime = try await service.available().first(where: { $0.major == major && $0.architecture == architecture }) else { throw RuriError.message(Messages.CoreOptiFineInstaller.javaRequiredForGeneration(String(describing: major))) }
                java = try await service.install(runtime, downloader: downloader, progress: progress); runtimes.append(java)
            }
            await progress(InstallProgress(Messages.CoreOptiFineInstaller.generatePatchLibrary))
            let runner = InstallerProcess(), log = paths.instance(instance.id).appendingPathComponent("installer.log")
            let status = try await runner.run(java: java, arguments: ["-Djava.awt.headless=true", "-cp", file.path, "optifine.Patcher", vanilla.path, file.path, patched.path],
                                             directory: work, logURL: log, runtimePaths: paths) { line in await progress(InstallProgress(line)) }
            guard status == 0 else { throw RuriError.message(Messages.CoreOptiFineInstaller.patchGenerationFailed(String(describing: status), log.path)) }
        } else { try FileManager.default.copyItem(at: file, to: patched) }
        let normalized = work.appendingPathComponent("optifine.jar")
        try Self.normalize(patched, to: normalized)
        var outputs: [(String, String, URL)] = [(coordinate, directory + URL(fileURLWithPath: relative).lastPathComponent, normalized)]
        if archive["launchwrapper-of.txt"] != nil {
            let wrapperVersion = String(decoding: try Self.read("launchwrapper-of.txt", in: archive), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard wrapperVersion.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreOptiFineInstaller.invalidLaunchWrapperVersion) }
            let wrapper = work.appendingPathComponent("launchwrapper.jar")
            try Self.read("launchwrapper-of-" + wrapperVersion + ".jar", in: archive).write(to: wrapper)
            let name = "optifine:launchwrapper-of:" + wrapperVersion
            outputs.append((name, try Library.mavenPath(name), wrapper))
        } else if archive["launchwrapper-2.0.jar"] != nil {
            let wrapper = work.appendingPathComponent("launchwrapper.jar")
            try Self.read("launchwrapper-2.0.jar", in: archive).write(to: wrapper)
            outputs.append(("optifine:launchwrapper:2.0", try Library.mavenPath("optifine:launchwrapper:2.0"), wrapper))
        }
        let prepared = try outputs.map { name, path, source -> (Library, URL) in
            let artifact = Artifact(path: path, url: nil, sha1: try InstanceTransfer.sha1(source), size: Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0))
            if let expected {
                guard let original = expected.first(where: { $0.path == path }), original.sha1 == artifact.sha1 else { throw RuriError.message(Messages.CoreOptiFineInstaller.regeneratedPackageMismatch) }
            }
            return (Library(name: name, downloads: .init(artifact: artifact), rules: nil, natives: nil, extract: nil), source)
        }
        for (library, source) in prepared { try publish(source, to: resources.libraryFile(library.downloads!.artifact!)) }
        let installerPath = directory + URL(fileURLWithPath: relative).deletingPathExtension().lastPathComponent + "-installer.jar"
        let source = Artifact(path: installerPath, url: sourceURL, sha1: try InstanceTransfer.sha1(file), size: Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0))
        try publish(file, to: resources.libraryFile(source))
        var libraries = prepared.map(\.0)
        if outputs.count == 1 { libraries.append(Library(name: "net.minecraft:launchwrapper:1.12", downloads: nil, rules: nil, natives: nil, extract: nil)) }
        return (libraries, source)
    }

    static func metadata(_ archive: Archive) throws -> (game: String, version: String) {
        guard let name = ["Config.class", "net/optifine/Config.class", "notch/net/optifine/Config.class"].first(where: { archive[$0] != nil }) else { throw RuriError.message(Messages.CoreOptiFineInstaller.unsupportedInstallPackage) }
        let values = try OptiFineClassMetadata.values(read(name, in: archive))
        guard let game = values["MC_VERSION"], let edition = values["OF_EDITION"], let release = values["OF_RELEASE"] else { throw RuriError.message(Messages.CoreOptiFineInstaller.missingPackageVersion) }
        return (game, edition + "_" + release)
    }
    static func normalize(_ source: URL, to target: URL) throws {
        try FileManager.default.copyItem(at: source, to: target)
        do {
            let archive = try Archive(url: target, accessMode: .update)
            if let entry = archive["META-INF/mods.toml"] { try archive.remove(entry, bufferSize: 128 * 1024) }
        }
        var data = try Data(contentsOf: target)
        guard data.count >= 22, data.count <= 64 * 1024 * 1024 else { throw RuriError.message(Messages.CoreOptiFineInstaller.invalidPatchFileSize) }
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset + count <= data.count else { throw RuriError.message(Messages.CoreOptiFineInstaller.invalidZipStructure) }
            return (0..<count).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        let signature = Data([0x50, 0x4b, 0x05, 0x06])
        guard let end = data.range(of: signature, options: .backwards, in: max(0, data.count - 65_557)..<data.count)?.lowerBound,
              try end + 22 + number(end + 20, 2) == data.count,
              try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw RuriError.message(Messages.CoreOptiFineInstaller.invalidZipDirectory) }
        let count = try number(end + 10, 2), size = try number(end + 12, 4), start = try number(end + 16, 4)
        guard count < 30_000, start + size == end else { throw RuriError.message(Messages.CoreOptiFineInstaller.zipDirectoryTooLarge) }
        var offset = start
        // Keep compressed bytes intact. Rewriting each entry through ZIPFoundation
        // repeatedly rewrites the central directory and is quadratic in entry count.
        for _ in 0..<count {
            try Task.checkCancellation()
            guard try number(offset, 4) == 0x02014b50 else { throw RuriError.message(Messages.CoreOptiFineInstaller.invalidZipEntry) }
            let local = try number(offset + 42, 4)
            guard try number(local, 4) == 0x04034b50 else { throw RuriError.message(Messages.CoreOptiFineInstaller.invalidZipHeader) }
            let length = try 46 + number(offset + 28, 2) + number(offset + 30, 2) + number(offset + 32, 2)
            guard local + 14 <= start, offset + length <= end else { throw RuriError.message(Messages.CoreOptiFineInstaller.zipEntryOutOfRange) }
            let time = Data([0, 0, 0x21, 0]) // 1980-01-01 00:00 in DOS time.
            data.replaceSubrange((offset + 12)..<(offset + 16), with: time)
            data.replaceSubrange((local + 10)..<(local + 14), with: time)
            offset += length
        }
        guard offset == end else { throw RuriError.message(Messages.CoreOptiFineInstaller.zipEntryCountMismatch) }
        try data.write(to: target, options: .atomic)
        try SafeArchive.verify(target, maxBytes: 256 * 1024 * 1024)
    }
    private static func read(_ name: String, in archive: Archive) throws -> Data {
        guard let entry = archive[name], entry.type == .file, entry.uncompressedSize <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreOptiFineInstaller.missingPackageField(name)) }
        var data = Data(); let crc = try archive.extract(entry) { part in try Task.checkCancellation(); data.append(part) }
        guard crc == entry.checksum else { throw RuriError.message(Messages.CoreOptiFineInstaller.fileChecksumFailed) }
        return data
    }
    private func publish(_ source: URL, to target: URL) throws {
        if source.standardizedFileURL == target.standardizedFileURL { return }
        if FileManager.default.fileExists(atPath: target.path) {
            if try InstanceTransfer.sha1(source) == InstanceTransfer.sha1(target) { return }
            guard !protectExistingFiles, paths.repositoryImportID == nil else { throw RuriError.message(Messages.CoreOptiFineInstaller.dependencyReplacementRequired(target.lastPathComponent)) }
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).jar")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        guard rename(staging.path, target.path) == 0 else { throw RuriError.message(Messages.CoreOptiFineInstaller.dependencySaveFailed) }
    }
}
