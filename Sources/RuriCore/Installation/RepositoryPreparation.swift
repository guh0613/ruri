import RuriLocalization
import Foundation

extension MinecraftLibrarySelection {
    /// Local-hint dependencies retain their original repository-relative paths.
    /// The source JSON remains authoritative and is never rewritten on launch.
    func repositoryManifest(root: URL) throws -> VersionManifest {
        var result = manifest
        result.libraries = try libraries.map { declaration in
            var library = declaration.library
            guard let file = declaration.localFile else { return library }
            let prefix = root.path + "/"
            guard file.path.hasPrefix(prefix) else { throw RuriError.message(Messages.CoreRepositoryPreparation.dependencyOutsideGameFolder) }
            let original = try library.artifact()
            let local = Artifact(path: original?.path, url: nil, sha1: original?.sha1, size: original?.size, repositoryPath: String(file.path.dropFirst(prefix.count)))
            var downloads = library.downloads ?? .init(artifact: nil, classifiers: nil)
            downloads.artifact = local; library.downloads = downloads
            return library
        }
        return result
    }
}

extension GameInstaller {
    func prepareRepositoryNatives(_ instance: GameInstance, manifest: VersionManifest) throws {
        let resources = try paths.resources(for: instance), architecture = Self.architecture(for: manifest)
        let destination = try LauncherPaths.safePath("natives", within: paths.instance(instance.id))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for library in manifest.libraries where Self.allowed(library, architecture: architecture) {
            guard let native = try library.nativeArtifact(architecture: architecture) else { continue }
            let file = try resources.libraryFile(native, fallback: native.url.map { "natives/" + $0.lastPathComponent })
            guard FileManager.default.fileExists(atPath: file.path) else { throw RuriError.message(Messages.CoreRepositoryPreparation.missingNativeDependency(file.lastPathComponent)) }
            try SafeArchive.extract(file, to: destination, excluding: library.extract?.exclude ?? ["META-INF/"])
        }
    }
}
