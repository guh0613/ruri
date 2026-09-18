import RuriLocalization
import Foundation

private struct HMCLMetadata: Decodable {
    let name: String
    let gameVersion: String?
    let author: String?
    let version: String?
}

private struct HMCLVersion: Decodable {
    struct Identifier: Decodable {
        let value: String
        private enum CodingKeys: CodingKey { case id }
        init(from decoder: any Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) { value = text }
            else { value = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id) }
        }
    }
    let id: String?
    let jar: Identifier?
    let inheritsFrom: Identifier?
    let version: String?
    let hidden: Bool?
    let mainClass: String?
    let libraries: [Library]?
    let arguments: VersionManifest.Arguments?
    let minecraftArguments: String?
    let patches: [HMCLVersion]?
}

extension InstanceTransfer {
    static func describeHMCL(_ root: URL) throws -> InstanceImportDescription {
        let metadata = try JSONDecoder().decode(HMCLMetadata.self, from: read(root.appendingPathComponent("modpack.json")))
        let game = try LauncherPaths.safePath("minecraft", within: root)
        let manifest = try JSONDecoder().decode(HMCLVersion.self, from: read(game.appendingPathComponent("pack.json")))
        var nodes: [HMCLVersion] = [manifest]; var index = 0
        while index < nodes.count {
            guard nodes.count <= 1000 else { throw RuriError.message(Messages.CoreHMCLPack.tooManyManifestPatches) }
            nodes += nodes[index].patches ?? []; index += 1
        }
        let patches = Array(nodes.dropFirst())
        let libraries = nodes.flatMap { $0.libraries ?? [] }
        let version = manifest.jar?.value ?? metadata.gameVersion ?? patches.first(where: { $0.id == "game" })?.version ?? manifest.inheritsFrom?.value ?? manifest.id
        guard let version, version.range(of: #"^(?:[0-9]+(?:\.[0-9]+)*(?:[-_][A-Za-z0-9. -]+)?|[0-9]{2}w[0-9]{2}[a-z]|[abc][0-9][A-Za-z0-9._-]*|(?:rd|inf)-[0-9]+)$"#, options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreHMCLPack.unknownPackGameVersion) }
        let known = Set(["game", "fabric", "quilt", "forge", "neoforge", "legacyfabric", "liteloader", "optifine"])
        let unsupported = patches.filter { $0.hidden != true && $0.id != nil && !known.contains($0.id!) }.compactMap(\.id)
        guard unsupported.isEmpty else { throw RuriError.message(Messages.CoreHMCLPack.unsupportedPackComponents(String(describing: unsupported.joined(separator: "、")))) }
        for library in libraries {
            let parts = library.name.split(separator: ":")
            guard parts.count >= 3 else { throw RuriError.message(Messages.CoreHMCLPack.invalidDependencyCoordinates) }
            if String(parts[0]) == "com.cleanroommc" {
                throw RuriError.message(Messages.CoreHMCLPack.unsupportedPackComponent(String(describing: parts[0]), String(describing: parts[1])))
            }
        }
        var components: [LoaderKind: String] = [:]
        for patch in patches where patch.hidden != true {
            if let id = patch.id, let kind = LoaderKind(rawValue: id), kind != .vanilla, let value = patch.version { components[kind] = value }
        }
        let gameArguments = try nodes.flatMap { node in
            let modern = (node.arguments?.game ?? []).compactMap { if case .text(let text) = $0 { text } else { nil } }
            return modern + (try node.minecraftArguments.map(ArgumentTokenizer.split) ?? [])
        }
        func argument(_ key: String) -> String? {
            guard let index = gameArguments.firstIndex(of: key), index + 1 < gameArguments.count else { return nil }
            return gameArguments[index + 1]
        }
        func forgeVersion(_ value: String) -> String {
            let parts = value.split(separator: "-")
            if parts.count >= 2, parts[0] == Substring(version) { return String(parts[1]) }
            return value
        }
        let neo = libraries.contains { $0.name.hasPrefix("net.neoforged.fancymodloader:") || $0.name.hasPrefix("net.neoforged:neoforge:") || $0.name.hasPrefix("net.neoforged:forge:") }
        let legacyFabric = components[.legacyfabric] != nil || libraries.contains { $0.name.hasPrefix("net.legacyfabric:intermediary:") || $0.name.hasPrefix("net.legacyfabric:fabric-loader:") }
        if legacyFabric, let version = components.removeValue(forKey: .fabric), components[.legacyfabric] == nil { components[.legacyfabric] = version }
        for library in libraries {
            let parts = library.name.split(separator: ":").map(String.init)
            let coordinate = parts[0] + ":" + parts[1]; let value = parts[2].components(separatedBy: "@")[0]
            if coordinate == "com.mumfrey:liteloader", components[.liteloader] == nil { components[.liteloader] = value }
            if ["optifine:OptiFine", "net.optifine:OptiFine"].contains(coordinate), components[.optifine] == nil {
                components[.optifine] = OptiFineCatalog.normalized(value, game: version)
            }
            if ["net.fabricmc:fabric-loader", "net.legacyfabric:fabric-loader"].contains(coordinate) {
                let kind: LoaderKind = legacyFabric ? .legacyfabric : .fabric
                if components[kind] == nil { components[kind] = value }
            }
            if coordinate == "org.quiltmc:quilt-loader", components[.quilt] == nil { components[.quilt] = value }
            if !neo, ["net.minecraftforge:forge", "net.minecraftforge:fmlloader", "net.minecraftforge:minecraftforge"].contains(coordinate), components[.forge] == nil { components[.forge] = forgeVersion(value) }
            if neo, components[.neoforge] == nil {
                if let value = argument("--fml.neoForgeVersion") ?? argument("--fml.forgeVersion") { components[.neoforge] = value }
                else if ["net.neoforged:neoforge", "net.neoforged:forge"].contains(coordinate) { components[.neoforge] = forgeVersion(value) }
            }
        }
        guard !neo || components[.neoforge] != nil else { throw RuriError.message(Messages.CoreHMCLPack.neoforgeVersionUnknown) }
        let selections = LoaderSelection.ordered(components.map { LoaderSelection(loader: $0.key, version: $0.value) })
        try LoaderCompatibility.validate(selections, game: version)
        let loader = selections.first?.loader ?? .vanilla
        if gameArguments.contains(where: { ($0.lowercased().contains("optifine") && components[.optifine] == nil) || ($0.lowercased().contains("liteloader") && components[.liteloader] == nil) }) {
            throw RuriError.message(Messages.CoreHMCLPack.unsupportedLiteLoaderArguments)
        }
        if loader == .vanilla, gameArguments.contains("--tweakClass") { throw RuriError.message(Messages.CoreHMCLPack.unknownLaunchWrapper) }
        if loader == .vanilla, let main = nodes.compactMap(\.mainClass).last, !["net.minecraft.client.main.Main", "net.minecraft.launchwrapper.Launch", "net.minecraft.client.Minecraft", "com.mojang.rubydung.RubyDung"].contains(main) {
            throw RuriError.message(Messages.CoreHMCLPack.unknownLaunchMethod(String(describing: main)))
        }
        var instance = GameInstance(name: metadata.name, gameVersion: version)
        instance.setLoaderSelections(selections)
        try validate(instance)
        var warnings = [Messages.CoreHMCLPack.reinstallDependenciesForMac.localized]
        if let author = metadata.author, !author.isEmpty { warnings.append(Messages.CoreHMCLPack.packAuthor(String(describing: author)).localized) }
        return InstanceImportDescription(instance: instance, game: game, format: "HMCL", warnings: warnings, excluded: ["pack.json"], modpack: ModpackDescriptor(version: metadata.version ?? ""))
    }
}
