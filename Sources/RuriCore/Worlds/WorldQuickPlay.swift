import Foundation
import Darwin

/// A one-launch destination. It never becomes a persistent instance argument.
public enum WorldQuickPlay {
    public static func supports(instance: GameInstance, manifest: VersionManifest) -> Bool {
        let features = ["has_quick_plays_support": true, "is_quick_play_singleplayer": true]
        let declared = (manifest.arguments?.game ?? []).flatMap { $0.values(architecture: GameInstaller.architecture(for: manifest), features: features) }
        if declared.contains("--quickPlaySingleplayer") || declared.contains(where: { $0.hasPrefix("--quickPlaySingleplayer=") }) { return true }
        // Local/merged manifests may omit Mojang's optional argument blocks.
        // HMCL uses the same release/snapshot boundary for this game feature.
        let value = instance.gameVersion
        if value.range(of: #"^1\.[0-9]+(?:\.[0-9]+)?(?:-(?:pre|rc)[0-9]+)?$"#, options: .regularExpression) != nil,
           let minor = Int(value.split(separator: ".")[1].split(separator: "-")[0]), minor >= 20 { return true }
        if value.range(of: #"^[0-9]{2}w[0-9]{2}[a-z]$"#, options: .regularExpression) != nil {
            return value >= "23w14a"
        }
        return false
    }
    public static func requireSupport(instance: GameInstance, manifest: VersionManifest) throws {
        guard supports(instance: instance, manifest: manifest) else { throw RuriError.message("此版本不支持直接进入存档，请启动游戏后从单人游戏菜单选择世界。") }
    }
    public static func selection(folder: String, instanceID: UUID, paths: LauncherPaths) throws -> WorldSnapshot {
        guard !folder.isEmpty, folder != ".", folder != "..", !folder.contains("/"), !folder.contains("\\"),
              !folder.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuriError.message("无效的存档目录名。") }
        try paths.validateInstanceLocation(instanceID)
        let saves = paths.game(instanceID).appendingPathComponent("saves")
        let world = try LauncherPaths.safePath(folder, within: saves)
        let info = try world.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw RuriError.message("存档已移除或不是有效的文件夹，请刷新存档列表。") }
        let file = world.appendingPathComponent(FileManager.default.fileExists(atPath: world.appendingPathComponent("level.dat").path) ? "level.dat" : "level.dat_old")
        var reader = try NBTReader(data: RunDirectoryCopyGuard.read(file, limit: 32 * 1024 * 1024))
        guard let data = try reader.read()["Data"], case .compound = data else { throw RuriError.message("存档信息不完整，请先在游戏中检查此世界。") }
        let lock = try WorldManager.readLock(world); defer { if let lock { close(lock) } }
        return .init(folder: folder, url: world, name: data["LevelName"]?.string ?? folder, version: data["Version"]?["Name"]?.string,
                     gameMode: nil, lastPlayed: nil, size: nil, icon: nil, metadataError: nil)
    }
    static func validate(_ world: WorldSnapshot, instance: GameInstance, manifest: VersionManifest, paths: LauncherPaths) throws {
        try requireSupport(instance: instance, manifest: manifest)
        let current = try selection(folder: world.folder, instanceID: instance.id, paths: paths)
        guard current.url.standardizedFileURL.resolvingSymlinksInPath() == world.url.standardizedFileURL.resolvingSymlinksInPath() else {
            throw RuriError.message("实例运行目录在选择存档后改变，请重新选择世界。")
        }
    }
    static func applying(_ world: WorldSnapshot, to arguments: [String], instance: GameInstance, paths: LauncherPaths) -> [String] {
        // The clicked world owns this launch's destination, including when a
        // pack or saved extra arguments contain an older quick-play target.
        let replaced: Set<String> = ["--quickPlaySingleplayer", "--quickPlayMultiplayer", "--quickPlayRealms", "--quickPlayPath", "--server", "--port", "--gameDir"]
        var result: [String] = [], index = 0
        while index < arguments.count {
            let value = arguments[index], key = String(value.split(separator: "=", maxSplits: 1).first ?? "")
            if replaced.contains(key) { index += value.contains("=") ? 1 : min(2, arguments.count - index) }
            else { result.append(value); index += 1 }
        }
        return result + ["--quickPlaySingleplayer", world.folder, "--gameDir", paths.game(instance.id).path,
                         "--quickPlayPath", paths.instance(instance.id).appendingPathComponent("quick-play.json").path]
    }
}
