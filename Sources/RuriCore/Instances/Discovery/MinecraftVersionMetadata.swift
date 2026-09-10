import Foundation
import ZIPFoundation

extension MinecraftDirectoryScan {
    struct VersionMetadata {
        let gameVersion: String?
        let components: [MinecraftDirectoryComponent]
        let warnings: [String]
    }
    mutating func version(_ id: String) throws -> VersionMetadata {
        var chain: [(String, [String: Any])] = [], seen: Set<String> = []
        var current: String? = id
        while let name = current {
            try Task.checkCancellation()
            guard seen.insert(name).inserted, seen.count <= 32 else { throw RuriError.message("版本继承存在循环或层级过深。") }
            try Self.checkIdentifier(name)
            let value = try object(path("versions/\(name)/\(name).json"))
            chain.append((name, value)); current = try Self.identifier(value["inheritsFrom"])
        }
        var nodes: [[String: Any]] = []
        for (_, value) in chain.reversed() {
            var pending = [value], index = 0
            while index < pending.count {
                guard nodes.count < 1_024 else { throw RuriError.message("版本组件数量超过读取限制。") }
                let node = pending[index]; index += 1; nodes.append(node)
                if let patches = node["patches"] {
                    guard let patches = patches as? [[String: Any]] else { throw RuriError.message("版本补丁清单格式无效。") }
                    pending += patches
                }
            }
        }
        let arguments = try nodes.flatMap { node -> [String] in
            let modern = (node["arguments"] as? [String: Any])?["game"] as? [Any] ?? []
            return modern.compactMap { $0 as? String } + (try (node["minecraftArguments"] as? String).map(ArgumentTokenizer.split) ?? [])
        }
        func argument(_ key: String) -> String? {
            guard let index = arguments.lastIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let declared = nodes.reversed().compactMap { $0["clientVersion"] as? String }.first
            ?? nodes.last(where: { ($0["id"] as? String) == "game" })?["version"] as? String
            ?? argument("--fml.mcVersion")
        let reference = try chain.compactMap { try Self.identifier($0.1["jar"]) }.first ?? chain.last!.0
        try Self.checkIdentifier(reference)
        let jar = try path("versions/\(reference)/\(reference).jar")
        var warnings: [String] = []
        var jarVersion: String?
        if exists(jar) {
            do { jarVersion = try Self.jarVersion(jar) }
            catch is CancellationError { throw CancellationError() }
            catch { warnings.append("无法从游戏 JAR 读取版本信息：\(error.localizedDescription)") }
        } else { warnings.append("本地游戏 JAR 缺失，接入时需要补齐游戏文件。") }
        let gameVersion = [jarVersion, declared].compactMap { $0 }.first(where: { !$0.isEmpty && $0.count <= 128 && !$0.contains("/") && !$0.contains("\\") && !$0.contains("\0") })
            ?? [reference, chain.last!.0].first(where: Self.isGameVersion)
        if gameVersion == nil { warnings.append("无法确定实际 Minecraft 版本，不能仅按文件夹名称判断。") }
        if let jarVersion, let declared, jarVersion != declared { warnings.append("游戏 JAR 与清单声明的版本不同，需要在接入前核对。") }
        var components: [String: String] = [:]
        let labels = ["fabric": "Fabric", "quilt": "Quilt", "forge": "Forge", "neoforge": "NeoForge", "optifine": "OptiFine", "liteloader": "LiteLoader", "legacyfabric": "Legacy Fabric", "cleanroom": "Cleanroom"]
        for node in nodes {
            if let name = node["id"] as? String, let label = labels[name.lowercased()], let version = node["version"] as? String { components[label] = version }
            if let libraries = node["libraries"] {
                guard let libraries = libraries as? [[String: Any]], libraries.count <= 10_000 else { throw RuriError.message("依赖库清单格式或数量无效。") }
                for library in libraries {
                    guard let name = library["name"] as? String else { throw RuriError.message("依赖库缺少名称。") }
                    let parts = name.split(separator: ":").map(String.init)
                    guard parts.count >= 3 else { throw RuriError.message("依赖库坐标无效：\(name)") }
                    let coordinate = parts[0] + ":" + parts[1], version = parts[2].components(separatedBy: "@")[0]
                    switch coordinate {
                    case "net.fabricmc:fabric-loader": components["Fabric"] = version
                    case "org.quiltmc:quilt-loader": components["Quilt"] = version
                    case "net.minecraftforge:forge", "net.minecraftforge:fmlloader", "net.minecraftforge:minecraftforge":
                        components["Forge"] = Self.forgeVersion(version, game: gameVersion)
                    case "net.neoforged:neoforge", "net.neoforged:forge":
                        components["NeoForge"] = Self.forgeVersion(version, game: gameVersion)
                    case "optifine:OptiFine", "net.optifine:OptiFine": components["OptiFine"] = version
                    case "com.mumfrey:liteloader": components["LiteLoader"] = version
                    case "net.legacyfabric:fabric-loader": components["Legacy Fabric"] = version
                    case "com.cleanroommc:cleanroom": components["Cleanroom"] = version
                    default: break
                    }
                }
            }
        }
        if let neo = argument("--fml.neoForgeVersion") { components["NeoForge"] = neo; components.removeValue(forKey: "Forge") }
        else if let forge = argument("--fml.forgeVersion"), components["NeoForge"] == nil { components["Forge"] = forge }
        if components.isEmpty, let main = nodes.reversed().compactMap({ $0["mainClass"] as? String }).first,
           !["net.minecraft.client.main.Main", "net.minecraft.client.Minecraft", "com.mojang.rubydung.RubyDung"].contains(main) {
            warnings.append("此版本使用尚未识别的启动入口：\(main)")
        }
        return .init(gameVersion: gameVersion, components: components.sorted { $0.key < $1.key }.map { .init(name: $0.key, version: $0.value) }, warnings: warnings)
    }

    private static func identifier(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let value = value as? String { return value }
        if let value = value as? [String: Any], let id = value["id"] as? String { return id }
        throw RuriError.message("版本引用格式无效。")
    }
    private static func checkIdentifier(_ name: String) throws {
        guard !name.isEmpty, name.utf8.count <= 255, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw RuriError.message("版本名称或继承路径无效。") }
    }
    private static func isGameVersion(_ value: String) -> Bool {
        value.count <= 128 && value.range(of: #"^(?:[0-9]+(?:\.[0-9]+)*(?:(?:-pre|-rc)[0-9]+| Pre-Release [0-9]+| Release Candidate [0-9]+)?|[0-9]{2}w[0-9]{2}[a-z]|[abc][0-9][A-Za-z0-9._-]*|(?:rd|inf)-[0-9]+)$"#, options: .regularExpression) != nil
    }
    private static func forgeVersion(_ value: String, game: String?) -> String {
        guard let game, value.hasPrefix(game + "-") else { return value }
        return String(value.dropFirst(game.count + 1))
    }
    private static func jarVersion(_ jar: URL) throws -> String? {
        let info = try jar.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw RuriError.message("游戏 JAR 不是普通文件。") }
        let archive = try Archive(url: jar, accessMode: .read)
        guard let entry = archive["version.json"] else { return nil }
        guard entry.type == .file, entry.uncompressedSize <= 1_048_576 else { throw RuriError.message("JAR 的版本信息过大或格式无效。") }
        var data = Data()
        let crc = try archive.extract(entry) { part in
            try Task.checkCancellation()
            guard data.count + part.count <= 1_048_576 else { throw RuriError.message("JAR 的版本信息超过限制。") }
            data.append(part)
        }
        guard crc == entry.checksum else { throw RuriError.message("JAR 的版本信息校验失败。") }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
    }
}
