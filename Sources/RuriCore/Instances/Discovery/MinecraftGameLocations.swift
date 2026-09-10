import Foundation

extension MinecraftDirectoryScan {
    struct Locations {
        let values: [MinecraftGameLocation]
        let suggested: String?
        let warnings: [String]
    }
    mutating func locations(version: String, directory: URL) throws -> Locations {
        var values: [MinecraftGameLocation] = [], warnings: [String] = [], configured: [URL] = []
        func location(_ url: URL, title: String, explanation: String) throws -> MinecraftGameLocation {
            let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let available = info?.isDirectory == true && info?.isSymbolicLink != true
            let labels = [("saves", "存档"), ("mods", "模组"), ("config", "模组配置"), ("resourcepacks", "资源包"), ("shaderpacks", "光影"), ("options.txt", "游戏设置")]
            let contents = available ? labels.compactMap { FileManager.default.fileExists(atPath: url.appendingPathComponent($0.0).path) ? $0.1 : nil } : []
            return .init(directory: url, title: title, explanation: explanation, available: available, contents: contents)
        }
        values.append(try location(root, title: "共享游戏目录", explanation: "此 Minecraft 目录中的多个版本可能共用这些存档、模组和设置。"))
        values.append(try location(directory, title: "版本独立目录", explanation: "启用版本隔离时，游戏数据通常位于这个版本文件夹。"))
        func custom(_ value: String, title: String) throws -> URL? {
            guard value.hasPrefix("/"), !value.contains("\0"), value.utf8.count <= 4_096 else { return nil }
            let url = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            if !values.contains(where: { $0.directory == url }) {
                values.append(try location(url, title: title, explanation: "原启动器为此版本指定的游戏数据位置。"))
            }
            return url
        }
        // A modpack's instance directory overrides the launcher's global preset.
        let modpackFile = directory.appendingPathComponent("modpack.cfg")
        if exists(modpackFile) {
            _ = try read(modpackFile); configured = [directory]
        } else {
            let modernFile = directory.appendingPathComponent(".hmcl/config/instance-game-settings.json")
            let legacyFile = directory.appendingPathComponent("hmclversion.cfg")
            if let settings = try optionalObject(modernFile) {
                if (settings["overrideProperties"] as? [String] ?? []).contains("runningDirectory") {
                    let value = (settings["runningDirectory"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty { configured = [directory] }
                    else if let url = try custom(value, title: "HMCL 自定义目录") { configured = [url] }
                    else { warnings.append("HMCL 的自定义目录不是可直接使用的 macOS 绝对路径，请手动确认游戏数据位置。") }
                } else { warnings.append("此版本继承 HMCL 的全局目录设置，请确认实际使用的存档和模组目录。") }
            } else if let settings = try optionalObject(legacyFile) {
                if (settings["usesGlobal"] as? Bool) == true { warnings.append("此版本继承旧版 HMCL 的全局设置，请确认游戏数据位置。") }
                else {
                    let type: String
                    if let name = settings["gameDirType"] as? String { type = name }
                    else if let index = settings["gameDirType"] as? Int, (0...2).contains(index) { type = ["ROOT_FOLDER", "VERSION_FOLDER", "CUSTOM"][index] }
                    else { type = "UNKNOWN" }
                    switch type {
                    case "ROOT_FOLDER": configured = [root]
                    case "VERSION_FOLDER": configured = [directory]
                    case "CUSTOM":
                        if let path = settings["gameDir"] as? String, let url = try custom(path, title: "HMCL 自定义目录") { configured = [url] }
                        else { warnings.append("旧版 HMCL 的自定义目录无法定位，请手动确认。") }
                    default: warnings.append("无法读取旧版 HMCL 的目录策略，请确认游戏数据位置。")
                    }
                }
            } else if let profiles = try optionalObject(root.appendingPathComponent("launcher_profiles.json"))?["profiles"] as? [String: [String: Any]] {
                guard profiles.count <= 2_000 else { throw RuriError.message("官方启动器配置数量超过读取限制。") }
                for (_, profile) in profiles.sorted(by: { $0.key < $1.key }) where (profile["lastVersionId"] as? String) == version {
                    if let value = profile["gameDir"] as? String, !value.isEmpty {
                        if let url = try custom(value, title: "官方启动器自定义目录") { configured.append(url) }
                        else { warnings.append("一个官方启动器配置使用了无法定位的游戏目录，请确认要接入哪个配置。") }
                    } else { configured.append(root) }
                }
            }
        }
        if !exists(modpackFile) { documents.append(.init(url: modpackFile, data: nil)) }
        let unique = Set(configured.map { $0.path })
        let suggested = unique.count == 1 && warnings.isEmpty ? unique.first : nil
        if unique.count > 1 { warnings.append("此版本有多个启动配置，使用不同游戏目录；请选择本次要接入的内容。") }
        if suggested == nil && warnings.isEmpty { warnings.append("没有找到明确的运行目录设置，请选择存档、模组实际所在的位置。") }
        return .init(values: values, suggested: suggested, warnings: warnings)
    }
}
