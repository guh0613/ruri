import RuriLocalization
import Foundation
import CryptoKit

public struct ModpackExportDetails: Sendable {
    public var version: String
    public var author: String
    public var description: String
    public var referenceDownloads: Bool
    public init(version: String = "1.0.0", author: String = "", description: String = "", referenceDownloads: Bool = true) { self.version = version; self.author = author; self.description = description; self.referenceDownloads = referenceDownloads }
}

struct MCBBSManifest: Codable {
    struct Addon: Codable { let id: String; let version: String }
    struct File: Codable {
        let type: String
        var force: Bool? = true
        var path: String?
        var hash: String?
        var projectID: Int?
        var fileID: Int?
    }
    struct LaunchInfo: Codable {
        var minMemory: Int?
        var supportJava: [Int]?
        var launchArgument: [String]?
        var javaArgument: [String]?
    }
    let manifestType: String
    let manifestVersion: Int
    let name: String
    var version: String?
    var author: String?
    var description: String?
    var fileApi: String?
    var forceUpdate: Bool?
    let addons: [Addon]
    var libraries: [Library]?
    let files: [File]
    var launchInfo: LaunchInfo?
}

extension InstanceTransfer {
    static func describeMCBBS(_ root: URL, filename: String = "mcbbs.packmeta") throws -> InstanceImportDescription {
        let source = try read(root.appendingPathComponent(filename))
        let manifest = try JSONDecoder().decode(MCBBSManifest.self, from: source)
        guard manifest.manifestType == "minecraftModpack", [1, 2].contains(manifest.manifestVersion),
              Set(manifest.addons.map(\.id)).count == manifest.addons.count,
              let gameVersion = manifest.addons.first(where: { $0.id == "game" })?.version else { throw RuriError.message(Messages.CoreMCBBSPack.invalidPackGameVersion) }
        let supported = Set(["game", "fabric", "quilt", "forge", "neoforge", "legacyfabric", "liteloader", "optifine"])
        let unknown = manifest.addons.filter { !supported.contains($0.id) }
        guard unknown.isEmpty else { throw RuriError.message(Messages.CoreMCBBSPack.unsupportedPackComponents(String(describing: unknown.map(\.id).joined(separator: "、")))) }
        let loaders = manifest.addons.filter { $0.id != "game" }
        let selections = loaders.compactMap { addon in LoaderKind(rawValue: addon.id).map { LoaderSelection(loader: $0, version: addon.version) } }
        try LoaderCompatibility.validate(selections, game: gameVersion)
        var instance = GameInstance(name: manifest.name, gameVersion: gameVersion)
        instance.setLoaderSelections(selections)
        if let minimum = manifest.launchInfo?.minMemory {
            guard (0...131_072).contains(minimum) else { throw RuriError.message(Messages.CoreMCBBSPack.invalidPackMemoryRequirement) }
            if minimum > 0 { instance.memoryMB = max(minimum, 512) }
        }
        instance.supportedJavaMajors = manifest.launchInfo?.supportJava
        instance.extraJVMArguments = ArgumentTokenizer.join(manifest.launchInfo?.javaArgument ?? [])
        instance.extraGameArguments = manifest.launchInfo?.launchArgument.map(ArgumentTokenizer.join)
        let gameArguments = manifest.launchInfo?.launchArgument ?? []
        for (flag, key) in [("--width", \GameInstance.width), ("--height", \GameInstance.height)] {
            if let index = gameArguments.lastIndex(of: flag), index + 1 < gameArguments.count, let value = Int(gameArguments[index + 1]) { instance[keyPath: key] = value }
        }
        instance.packLibraries = manifest.libraries
        // What the pack spells out stays with the instance; everything else
        // follows the global settings like a new instance.
        var overrides = InstanceLaunchOverrides()
        if (manifest.launchInfo?.minMemory ?? 0) > 0 { overrides.memory = .init(maximumMB: instance.memoryMB) }
        if !instance.extraJVMArguments.isEmpty { overrides.jvmArguments = instance.extraJVMArguments }
        if let arguments = instance.extraGameArguments, !arguments.isEmpty { overrides.gameArguments = arguments }
        if gameArguments.contains("--width") || gameArguments.contains("--height") { overrides.window = .init(width: instance.width, height: instance.height) }
        instance.launchOverrides = overrides
        try validate(instance)
        let game = try LauncherPaths.safePath("overrides", within: root)
        if FileManager.default.fileExists(atPath: game.path) {
            let info = try game.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw RuriError.message(Messages.CoreMCBBSPack.invalidOverridesDirectory) }
        }
        guard manifest.files.count <= 100_000 else { throw RuriError.message(Messages.CoreMCBBSPack.packFileCountExceeded) }
        var files: [PackFile] = []; var curse: [CurseForgeReference] = []
        for file in manifest.files {
            switch file.type {
            case "addon":
                guard let path = file.path, let hash = file.hash, hash.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreMCBBSPack.missingFileHash) }
                _ = try LauncherPaths.safePath(path, within: game)
                guard !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." }) else { throw RuriError.message(Messages.CoreMCBBSPack.invalidPackFilePath(path)) }
                var url: URL?
                if let value = manifest.fileApi, !value.isEmpty {
                    guard let base = URL(string: value), ["http", "https"].contains(base.scheme), base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw RuriError.message(Messages.CoreMCBBSPack.invalidFileApiSource) }
                    url = try EndpointURL.build(base: base, path: ["overrides"] + path.split(separator: "/").map(String.init))
                }
                files.append(PackFile(path: path, sha1: hash.lowercased(), url: url, force: file.force ?? false))
            case "curse":
                guard let project = file.projectID, let id = file.fileID, project > 0, id > 0 else { throw RuriError.message(Messages.CoreMCBBSPack.invalidCurseForgeFileID) }
                // force controls online replacement, not whether a file is optional.
                curse.append(CurseForgeReference(projectID: project, fileID: id, required: true))
            default: throw RuriError.message(Messages.CoreMCBBSPack.unsupportedPackFileType(String(describing: file.type)))
            }
        }
        guard Set(files.map { $0.path.lowercased() }).count == files.count, Set(curse.map(\.projectID)).count == curse.count else { throw RuriError.message(Messages.CoreMCBBSPack.duplicatePackPathOrProject) }
        var warnings: [String] = []
        if let author = manifest.author, !author.isEmpty { warnings.append(Messages.CoreMCBBSPack.packAuthor(String(describing: author)).localized) }
        if !instance.extraJVMArguments.isEmpty { warnings.append(Messages.CoreMCBBSPack.packJvmArgumentsNotice.localized) }
        if manifest.fileApi?.isEmpty == false { warnings.append(Messages.CoreMCBBSPack.packMissingFilesNotice.localized) }
        if !curse.isEmpty { warnings.append(Messages.CoreMCBBSPack.curseForgeFilesToResolve(Int64(curse.count)).localized) }
        let origin = manifest.fileApi.flatMap { $0.isEmpty ? nil : URL(string: $0) }.map { ModpackOrigin(provider: .mcbbs, fileAPI: $0) }
        return InstanceImportDescription(instance: instance, game: game, format: "MCBBS", warnings: warnings, curseForgeFiles: curse, packFiles: files, sourceMetadata: source, modpack: ModpackDescriptor(version: manifest.version ?? "", origin: origin, forcedProjects: Set(manifest.files.filter { $0.type == "curse" && $0.force == true }.compactMap { $0.projectID.map(String.init) })))
    }

    func exportMCBBS(_ instance: GameInstance, game: URL, to destination: URL, includeWorlds: Bool, details: ModpackExportDetails, progress: @Sendable (InstallProgress) -> Void) throws {
        guard !details.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, details.version.count <= 128, details.author.count <= 256, details.description.count <= 32_768 else { throw RuriError.message(Messages.CoreMCBBSPack.invalidPackMetadata) }
        let workspace = paths.cache.appendingPathComponent("export-mcbbs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let snapshot = workspace.appendingPathComponent("overrides")
        try FileTree.copy(from: game, to: snapshot, excluding: Self.exclusions(game, includeWorlds: includeWorlds)) { done, total in progress(InstallProgress(Messages.CoreMCBBSPack.preparingPack, completed: done, total: total)) }
        let entries = try FileTree.entries(in: snapshot)
        var files: [MCBBSManifest.File] = []
        for entry in entries where !entry.directory {
            try Task.checkCancellation()
            files.append(.init(type: "addon", path: entry.path, hash: try Self.sha1(entry.url)))
        }
        var addons = [MCBBSManifest.Addon(id: "game", version: instance.gameVersion)]
        for selection in instance.loaderSelections {
            guard !selection.version.isEmpty else { throw RuriError.message(Messages.CoreMCBBSPack.loaderInstallRequiredForExport) }
            addons.append(.init(id: selection.loader.rawValue, version: selection.version))
        }
        var gameArguments = try ArgumentTokenizer.split(instance.extraGameArguments ?? "")
        if !gameArguments.contains("--width") { gameArguments += ["--width", String(instance.width)] }
        if !gameArguments.contains("--height") { gameArguments += ["--height", String(instance.height)] }
        if instance.fullscreen == true && !gameArguments.contains(where: { $0 == "--fullscreen" || $0.hasPrefix("--fullscreen=") }) { gameArguments.append("--fullscreen") }
        let manifest = MCBBSManifest(manifestType: "minecraftModpack", manifestVersion: 2, name: instance.name, version: details.version, author: details.author, description: details.description, forceUpdate: false,
                                     addons: addons, libraries: instance.packLibraries ?? [], files: files,
                                     launchInfo: .init(minMemory: instance.memoryMB, supportJava: instance.supportedJavaMajors ?? [],
                                                       launchArgument: gameArguments, javaArgument: try ArgumentTokenizer.split(instance.extraJVMArguments)))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let loaders = instance.loaderSelections.enumerated().map { index, selection in
            ["id": selection.loader.rawValue + "-" + selection.version, "primary": index == 0] as [String: Any]
        }
        let compatible: [String: Any] = ["manifestType": "minecraftModpack", "manifestVersion": 1, "name": instance.name, "version": details.version, "author": details.author, "overrides": "overrides",
                                        "minecraft": ["version": instance.gameVersion, "modLoaders": loaders], "files": []]
        let extras = ["mcbbs.packmeta": try encoder.encode(manifest), "manifest.json": try JSONSerialization.data(withJSONObject: compatible, options: [.prettyPrinted, .sortedKeys])]
        try SafeArchive.create(from: snapshot, to: destination, prefix: "overrides", additionalFiles: extras) { done, total in progress(InstallProgress(Messages.CoreMCBBSPack.exportingMCBBSPack, completed: done, total: total)) }
    }
    static func sha1(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = Insecure.SHA1()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
