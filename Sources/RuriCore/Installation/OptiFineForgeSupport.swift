import Foundation
import CryptoKit
import RuriLocalization
import ZIPFoundation

enum OptiFineForgeSupport {
    enum LaunchKind { case launchWrapper, modLauncher, bootstrap, forgeBootstrap }
    static let discoveryName = "org.ruri:transformer-discovery:1.0"
    static let archiveProperty = "-Druri.optifine.archive="

    static func launchKind(_ manifest: VersionManifest) -> LaunchKind? {
        switch manifest.mainClass {
        case "net.minecraft.launchwrapper.Launch": .launchWrapper
        case "cpw.mods.modlauncher.Launcher": .modLauncher
        case "cpw.mods.bootstraplauncher.BootstrapLauncher": .bootstrap
        case "net.minecraftforge.bootstrap.ForgeBootstrap": .forgeBootstrap
        default: nil
        }
    }

    static func validatePackage(_ archive: Archive, kind: LaunchKind) throws {
        if kind == .launchWrapper {
            guard archive["optifine/OptiFineForgeTweaker.class"] != nil else {
                throw RuriError.message(Messages.LoaderSelection.optiFineCombinationUnavailable)
            }
        } else {
            let service = "META-INF/services/cpw.mods.modlauncher.api.ITransformationService"
            guard archive[service] != nil, archive["optifine/OptiFineTransformationService.class"] != nil else {
                throw RuriError.message(Messages.LoaderSelection.optiFineTransformationUnavailable)
            }
            let registrations = String(decoding: try OptiFineInstaller.read(service, in: archive), as: UTF8.self)
                .components(separatedBy: .newlines).map { $0.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces) }
            guard registrations.contains("optifine.OptiFineTransformationService") else {
                throw RuriError.message(Messages.LoaderSelection.optiFineTransformationUnavailable)
            }
            if kind == .bootstrap, archive["buildof.txt"] != nil {
                let build = String(decoding: try OptiFineInstaller.read("buildof.txt", in: archive), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard build.compare("20210924-190833", options: .numeric) != .orderedAscending else {
                    throw RuriError.message(Messages.LoaderSelection.optiFineBootstrapTooOld)
                }
            }
        }
    }

    static func discoveryLibrary() throws -> Library {
        let data = try discoveryData()
        let hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Library(name: discoveryName, downloads: .init(artifact: Artifact(path: try Library.mavenPath(discoveryName), url: nil, sha1: hash, size: Int64(data.count))), rules: nil, natives: nil, extract: nil)
    }

    static func prepareDiscoveryLibrary(_ manifest: VersionManifest, resources: GameResourcePaths, protectExistingFiles: Bool) throws {
        for library in manifest.libraries where library.name == discoveryName {
            let bundled = try discoveryLibrary()
            guard let artifact = try library.artifact(), artifact.sha1 == bundled.downloads?.artifact?.sha1 else {
                throw RuriError.message(Messages.LoaderSelection.discoveryLibraryMismatch)
            }
            let file = try resources.libraryFile(artifact)
            if DownloadManager.valid(file, item: DownloadItem(artifact, to: file)) { continue }
            if protectExistingFiles, FileManager.default.fileExists(atPath: file.path) {
                throw RuriError.message(Messages.CoreOptiFineInstaller.dependencyReplacementRequired(file.lastPathComponent))
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try discoveryData().write(to: file, options: .atomic)
        }
    }

    private static func discoveryData() throws -> Data {
        guard let file = Bundle.module.url(forResource: "ruri-transformer-discovery-1.0", withExtension: "jar", subdirectory: "LoaderSupport") else {
            throw RuriError.message(Messages.LoaderSelection.discoveryLibraryMissing)
        }
        return try Data(contentsOf: file)
    }
}

extension OptiFineInstaller {
    func combinedProfile(instance: GameInstance, base: VersionManifest, installer file: URL, version: String, sourceURL: URL, expected: [Artifact]? = nil) throws -> VersionManifest {
        guard let kind = OptiFineForgeSupport.launchKind(base) else { throw RuriError.message(Messages.LoaderSelection.unsupportedLaunchMethod) }
        try SafeArchive.verify(file, maxBytes: 256 * 1024 * 1024)
        let archive = try Archive(url: file, accessMode: .read), metadata = try Self.metadata(archive)
        let game = ["1.8.0": "1.8", "1.9.0": "1.9"][metadata.game] ?? metadata.game
        guard game == instance.gameVersion, metadata.version == version else { throw RuriError.message(Messages.CoreOptiFineInstaller.packageVersionMismatch) }
        try OptiFineForgeSupport.validatePackage(archive, kind: kind)
        let name = "optifine:OptiFine:\(instance.gameVersion)_\(version):installer"
        let originalPath = try Library.mavenPath(name)
        let resources = try paths.resources(for: instance)
        var child = VersionManifest(id: instance.gameVersion + "-OptiFine-" + version, libraries: [])
        if kind == .launchWrapper {
            let artifact = Artifact(path: originalPath, url: sourceURL, sha1: try InstanceTransfer.sha1(file))
            try publish(file, to: resources.libraryFile(artifact))
            child.libraries = [Library(name: name, downloads: .init(artifact: artifact), rules: nil, natives: nil, extract: nil)]
            let arguments = ["--tweakClass", "optifine.OptiFineForgeTweaker"]
            if let legacy = base.minecraftArguments { child.minecraftArguments = try ArgumentTokenizer.join(ArgumentTokenizer.split(legacy) + arguments) }
            else { child.arguments = .init(game: arguments.map(LaunchArgument.text)) }
            return child
        }

        // Keep the original download for reproducible repair. The normalized
        // transformation archive must not be mistaken for an ordinary FML mod.
        let directory = (originalPath as NSString).deletingLastPathComponent + "/ruri/"
        let stem = "OptiFine-\(instance.gameVersion)_\(version)"
        let source = Artifact(path: directory + stem + "-installer.jar", url: sourceURL, sha1: try InstanceTransfer.sha1(file))
        try publish(file, to: resources.libraryFile(source))
        let normalized = paths.cache.appendingPathComponent("optifine-combined-" + UUID().uuidString + ".jar")
        defer { try? FileManager.default.removeItem(at: normalized) }
        try Self.normalize(file, to: normalized)
        let artifact = Artifact(path: directory + stem + "-combined.jar", url: nil, sha1: try InstanceTransfer.sha1(normalized))
        if let expected, !expected.contains(where: { $0.path == artifact.path && $0.sha1 == artifact.sha1 }) {
            throw RuriError.message(Messages.CoreOptiFineInstaller.regeneratedPackageMismatch)
        }
        try publish(normalized, to: resources.libraryFile(artifact))
        var library = Library(name: name, downloads: .init(artifact: artifact), rules: nil, natives: nil, extract: nil)
        if kind == .modLauncher {
            library.includeInClasspath = false
            child.libraries = [library, try OptiFineForgeSupport.discoveryLibrary()]
            child.arguments = .init(jvm: [.text(OptiFineForgeSupport.archiveProperty + "${library_directory}/" + artifact.path!)])
        } else {
            child.libraries = [library]
        }
        child.generatedLibraries = [source]
        return child
    }
}
