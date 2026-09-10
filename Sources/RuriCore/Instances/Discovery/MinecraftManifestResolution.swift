import Foundation

/// The original installation after structural inheritance/patch composition.
/// This is not an installed instance: library normalization, file verification,
/// macOS dependency preparation and publication still happen during import.
public struct MinecraftManifestResolution: Sendable {
    public let manifest: VersionManifest
    public let clientFile: URL
    public let libraries: [MinecraftLibraryDeclaration]
    public let warnings: [String]
    let sourceManifests: [MinecraftDirectoryDocument]
}

public struct MinecraftLibraryDeclaration: Sendable {
    public let library: Library
    /// HMCL's local hint resolves in the selected version's libraries folder,
    /// including declarations inherited from another version.
    public let localFile: URL?
    var sourceMetadata: Data?
    static func readMetadata(_ raw: [String: Any]) throws -> Self {
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        let library = try JSONDecoder().decode(Library.self, from: data)
        _ = try Library.mavenPath(library.name)
        return .init(library: library, localFile: nil, sourceMetadata: data)
    }
}

extension MinecraftDirectoryReader {
    public func resolveManifest(_ version: MinecraftDirectoryVersion, in catalog: MinecraftDirectoryCatalog) throws -> MinecraftManifestResolution { try resolveManifestNow(version, in: catalog) }

    nonisolated func resolveManifestNow(_ version: MinecraftDirectoryVersion, in catalog: MinecraftDirectoryCatalog) throws -> MinecraftManifestResolution {
        try validateNow(version, in: catalog)
        var reader = MinecraftDirectoryScan(root: catalog.directory)
        let graph = try reader.manifestGraph(version.id)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: JSONSerialization.data(withJSONObject: graph.value))
        guard let main = manifest.mainClass, !main.isEmpty else { throw RuriError.message("合并后的版本清单没有游戏主类，请检查原安装。") }
        guard let jarID = manifest.jar else { throw RuriError.message("合并后的版本清单缺少游戏 JAR 引用。") }
        let rawLibraries = graph.value["libraries"] as? [[String: Any]] ?? []
        guard rawLibraries.count == manifest.libraries.count else { throw RuriError.message("依赖库清单包含无效声明。") }
        let libraries = try rawLibraries.map { raw -> MinecraftLibraryDeclaration in
            try Task.checkCancellation()
            let declaration = try MinecraftLibraryDeclaration.readMetadata(raw), library = declaration.library
            let mavenPath = try Library.mavenPath(library.name)
            let hint = raw["hint"] ?? raw["MMC-hint"]
            if let hint, !(hint is NSNull), !(hint is String) { throw RuriError.message("依赖库的位置提示无效：\(library.name)") }
            guard (hint as? String) == "local" else { return declaration }
            let filename = raw["filename"] ?? raw["MMC-filename"]
            let name: String
            if let filename, !(filename is NSNull) {
                guard let value = filename as? String else { throw RuriError.message("本地依赖库的文件名无效：\(library.name)") }
                name = value
            } else { name = URL(fileURLWithPath: mavenPath).lastPathComponent }
            let folder = try reader.path("versions/\(version.id)/libraries")
            return .init(library: library, localFile: try LauncherPaths.safePath(name, within: folder), sourceMetadata: declaration.sourceMetadata)
        }
        let client = try reader.path("versions/\(jarID)/\(jarID).jar")
        // Recheck the scan snapshot after composition as another launcher may
        // have rewritten a parent or its directory settings during this read.
        try validateNow(version, in: catalog)
        return .init(manifest: manifest, clientFile: client, libraries: libraries, warnings: graph.warnings, sourceManifests: reader.documents)
    }
}
