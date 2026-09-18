import RuriLocalization
import Foundation
import CryptoKit

/// Captures the files actually used by a local installation. Copies preserve
/// local bytes and checksums instead of reinstalling a nominal loader version.
struct MinecraftInstallationCopy: Equatable, Sendable {
    struct Resource: Equatable, Sendable {
        let source: URL
        let path: String
        let sha1: String
        let size: Int64
    }
    let manifest: Data
    let client: Resource
    let resources: [Resource]
    let generatedResources: [String: Data]
    let sourceManifests: [String: Data]
    let inputs: [FileTree.Entry]
    let replacements: [String: String]
    var fileCount: Int { 2 + resources.count + generatedResources.count + sourceManifests.count }
    var bytes: Int64 { client.size + Int64(manifest.count) + resources.reduce(0) { $0 + $1.size } + (Array(generatedResources.values) + Array(sourceManifests.values)).reduce(0) { $0 + Int64($1.count) } }

    static func read(instance: GameInstance, copy: GameInstance, paths: LauncherPaths, portable: Bool = false, installationRoot: URL? = nil) throws -> Self {
        let source = try installationRoot.map { try GameResourcePaths(root: $0, confined: true) } ?? paths.resources(for: instance)
        let targetRoot = try paths.including(copy).resources(for: copy).root
        let name = try required(copy.repositoryVersionID ?? (copy.importedInstallation != nil ? "game" : nil))
        let targetVersion = copy.repositoryVersionID == nil ? targetRoot.appendingPathComponent("versions/" + name) : paths.including(copy).versionDirectory(copy.id)
        var manifest: VersionManifest
        var documents: [MinecraftDirectoryDocument]
        if let version = instance.repositoryVersionID {
            let reader = MinecraftDirectoryReader(), catalog = try reader.scanNow(source.root)
            guard let selected = catalog.versions.first(where: { $0.id == version }) else { throw RuriError.message(Messages.CoreMinecraftInstallationCopy.sourceVersionRemoved) }
            let resolution = try reader.resolveManifestNow(selected, in: catalog)
            manifest = try resolution.selectingLibraries().repositoryManifest(root: source.root)
            documents = resolution.sourceManifests
        } else {
            let file = installationRoot?.appendingPathComponent("version.json") ?? paths.manifest(instance.id), data = try RunDirectoryCopyGuard.read(file, limit: 8_388_608)
            manifest = try JSONDecoder().decode(VersionManifest.self, from: data)
            documents = [.init(url: file, data: data)]
        }
        guard manifest.mainClass != nil, manifest.inheritsFrom == nil else { throw RuriError.message(Messages.CoreMinecraftInstallationCopy.incompleteLaunchManifest) }
        let architecture = GameInstaller.architecture(for: manifest)
        var files: [String: Resource] = [:], inputs: [String: FileTree.Entry] = [:]
        var hashes: [String: (String, Int64)] = [:]
        var generated: [String: Data] = [:], originals: [String: Data] = [:]
        var replacements: [String: String] = [:]
        func inspect(_ url: URL) throws -> (String, Int64) {
            if let existing = hashes[url.path] { return existing }
            try Task.checkCancellation()
            let before = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard before.isRegularFile == true, before.isSymbolicLink != true, let size = before.fileSize else {
                throw RuriError.message(Messages.CoreMinecraftInstallationCopy.installationFileMissing(url.path))
            }
            let hash = try InstanceTransfer.sha1(url)
            let after = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else {
                throw RuriError.message(Messages.CoreMinecraftInstallationCopy.installationFileChanged)
            }
            inputs[url.path] = .init(url: url, path: "installation-inputs/" + sha1(Data(url.path.utf8)), directory: false, size: Int64(size), modified: before.contentModificationDate ?? .distantPast)
            hashes[url.path] = (hash, Int64(size)); return (hash, Int64(size))
        }
        func add(_ url: URL, as path: String) throws -> Resource {
            _ = try LauncherPaths.safePath(path, within: targetRoot)
            let (hash, size) = try inspect(url)
            let file = Resource(source: url, path: path, sha1: hash, size: size)
            if let previous = files[path], previous.sha1 != hash { throw RuriError.message(Messages.CoreMinecraftInstallationCopy.contentConflict(path)) }
            files[path] = file
            return file
        }
        func artifact(_ value: Artifact, fallback: String?, required: Bool) throws -> Artifact {
            let url = try source.libraryFile(value, fallback: fallback)
            if !FileManager.default.fileExists(atPath: url.path), !required { return value }
            let (hash, size) = try inspect(url)
            let relative: String
            if value.repositoryPath != nil {
                relative = "ruri-local/\(hash)/\(url.lastPathComponent)"
            } else { relative = try Self.required(value.path ?? fallback) }
            let file = try add(url, as: "libraries/" + relative)
            let target = targetRoot.appendingPathComponent(file.path)
            replacements[url.path] = portable ? "${library_directory}/" + relative : target.path
            if let old = value.path ?? fallback, old != relative {
                replacements["${library_directory}/" + old] = "${library_directory}/" + relative
            }
            return Artifact(path: relative, url: value.sha1.map({ $0.lowercased() != hash }) == true ? nil : value.url, sha1: hash, size: size)
        }
        let jarID = manifest.jar ?? instance.gameVersion
        let clientURL = try installationRoot == nil ? paths.clientJar(jarID, instance: instance) : LauncherPaths.safePath("versions/\(jarID)/\(jarID).jar", within: source.root)
        let (clientHash, clientSize) = try inspect(clientURL)
        let client = Resource(source: clientURL, path: name + ".jar", sha1: clientHash, size: clientSize)
        let oldClient = manifest.downloads?["client"]
        manifest.downloads = ["client": Artifact(url: oldClient?.sha1.map({ $0.lowercased() != clientHash }) == true ? nil : oldClient?.url, sha1: clientHash, size: clientSize)]
        replacements[clientURL.path] = portable ? "${primary_jar}" : targetVersion.appendingPathComponent(name + ".jar").path
        for index in manifest.libraries.indices {
            var library = manifest.libraries[index]
            let needed = GameInstaller.allowed(library, architecture: architecture)
            var downloads = library.downloads ?? .init()
            if let value = try library.artifact() { downloads.artifact = try artifact(value, fallback: Library.mavenPath(library.name), required: needed) }
            let native = try library.nativeArtifact(architecture: architecture)
            if library.downloads == nil, let native, let classifier = library.natives?["osx"] {
                downloads.classifiers = [classifier.replacingOccurrences(of: "${arch}", with: "64"): native]
            }
            if let classifiers = downloads.classifiers {
                for (key, value) in classifiers {
                    downloads.classifiers?[key] = try artifact(value, fallback: value.url.map { "natives/" + $0.lastPathComponent }, required: needed && value == native)
                }
            }
            library.downloads = downloads; manifest.libraries[index] = library
        }
        if let libraries = manifest.generatedLibraries { manifest.generatedLibraries = try libraries.map { try artifact($0, fallback: nil, required: true) } }
        if let index = manifest.assetIndex {
            let indexFile = try LauncherPaths.safePath("indexes/\(index.id).json", within: source.assets)
            let original = try RunDirectoryCopyGuard.read(indexFile, limit: 64 * 1024 * 1024)
            let decoded = try JSONDecoder().decode(AssetObjects.self, from: original)
            guard decoded.objects.count <= 150_000 else { throw RuriError.message(Messages.CoreMinecraftInstallationCopy.resourceIndexTooLarge) }
            var objects: [String: AssetObjects.Object] = [:], changed = false
            for (key, object) in decoded.objects.sorted(by: { $0.key < $1.key }) {
                _ = try MinecraftEndpoints.asset(hash: object.hash)
                let url = try LauncherPaths.safePath("objects/\(object.hash.prefix(2))/\(object.hash)", within: source.assets)
                let (hash, size) = try inspect(url)
                _ = try add(url, as: "assets/objects/\(hash.prefix(2))/\(hash)")
                objects[key] = .init(hash: hash, size: size)
                changed = changed || hash != object.hash || size != object.size
            }
            let indexEncoder = JSONEncoder(); indexEncoder.outputFormatting = [.sortedKeys]
            let data = changed ? try indexEncoder.encode(AssetObjects(objects: objects, virtual: decoded.virtual, map_to_resources: decoded.map_to_resources)) : original
            let hash = sha1(data), id = changed ? "ruri-" + hash : index.id
            if changed { generated["assets/indexes/\(id).json"] = data; _ = try inspect(indexFile) }
            else { _ = try add(indexFile, as: "assets/indexes/\(id).json") }
            manifest.assetIndex = .init(id: id, url: index.url, sha1: hash, size: Int64(data.count))
        }
        if let logging = manifest.logging?.client {
            let url = try LauncherPaths.safePath("log_configs/" + logging.file.id, within: source.assets)
            let file = try add(url, as: "assets/log_configs/" + logging.file.id)
            manifest.logging = .init(client: .init(argument: logging.argument, file: .init(id: logging.file.id, url: logging.file.url, sha1: file.sha1, size: file.size), type: logging.type))
        }
        for (index, document) in documents.enumerated() {
            if let data = document.data { originals["source-manifests/\(index).json"] = data; _ = try inspect(document.url) }
        }
        replacements[source.libraries.path] = portable ? "${library_directory}" : targetRoot.appendingPathComponent("libraries").path
        replacements[source.assets.path] = portable ? "${assets_root}" : targetRoot.appendingPathComponent("assets").path
        if portable || !MinecraftGameDataFiles.sameLocation(paths.game(instance.id), source.root) {
            replacements[paths.game(instance.id).path] = portable ? "${game_directory}" : targetVersion.path
        }
        if instance.repositoryVersionID != nil && (!portable || !MinecraftGameDataFiles.sameLocation(paths.game(instance.id), paths.versionDirectory(instance.id))) { replacements[paths.versionDirectory(instance.id).path] = portable ? "${version_directory}" : targetVersion.path }
        if portable { replacements[paths.instance(instance.id).appendingPathComponent("natives").path] = "${natives_directory}" }
        manifest.id = name; manifest.jar = name; manifest.inheritsFrom = nil
        func rewrite(_ value: String) -> String {
            if value == paths.game(instance.id).path { return portable ? "${game_directory}" : targetVersion.path }
            if value == "--gameDir=" + paths.game(instance.id).path { return "--gameDir=" + (portable ? "${game_directory}" : targetVersion.path) }
            return Self.rewrite(value, replacements: replacements)
        }
        func argument(_ value: LaunchArgument) -> LaunchArgument {
            switch value { case .text(let value): .text(rewrite(value)); case .conditional(let rules, let values): .conditional(rules, values.map(rewrite)) }
        }
        if var arguments = manifest.arguments {
            arguments.jvm = arguments.jvm?.map(argument)
            arguments.game = arguments.game?.map(argument)
            manifest.arguments = arguments
        }
        if let legacy = manifest.minecraftArguments { manifest.minecraftArguments = try ArgumentTokenizer.join(ArgumentTokenizer.split(legacy).map(rewrite)) }
        if let logging = manifest.logging?.client { manifest.logging = .init(client: .init(argument: rewrite(logging.argument), file: logging.file, type: logging.type)) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var document = try JSONSerialization.jsonObject(with: encoder.encode(manifest)) as! [String: Any]
        document["clientVersion"] = instance.gameVersion
        // Metadata-only patches retain components detected from HMCL patches
        // even when they have no recognizable Maven coordinate.
        let components = instance.repositoryComponents ?? instance.importedInstallation?.components ?? []
        document["patches"] = components.map { ["id": $0.name.lowercased().replacingOccurrences(of: " ", with: ""), "version": $0.version] }
        return .init(manifest: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]), client: client, resources: files.values.sorted { $0.path < $1.path },
                     generatedResources: generated, sourceManifests: originals, inputs: inputs.values.sorted { $0.url.path < $1.url.path }, replacements: replacements)
    }

    static func rewrite(_ input: String, replacements: [String: String]) -> String {
        // Replace each original path once, avoiding cascading substitutions when
        // the new version directory lives below the old shared game root.
        let pairs = replacements.filter { $0.key != $0.value }.sorted { $0.key.count > $1.key.count }
        var result = input, tokens: [(String, String)] = []
        for (offset, pair) in pairs.enumerated() {
            let token = "\u{001F}ruri-path-\(offset)\u{001F}"
            let pattern = NSRegularExpression.escapedPattern(for: pair.key) + "(?=$|[/\\s:;,\"'])"
            result = result.replacingOccurrences(of: pattern, with: token, options: .regularExpression); tokens.append((token, pair.value))
        }
        for (token, value) in tokens { result = result.replacingOccurrences(of: token, with: value) }
        return result
    }
    static func sha1(_ data: Data) -> String { Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func required(_ value: String?) throws -> String {
        guard let value, !value.isEmpty else { throw RuriError.message(Messages.CoreMinecraftInstallationCopy.copyPathMissing) }; return value
    }
}
