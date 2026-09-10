import Foundation

/// Installation resources and launcher configuration do not follow a game's
/// saves/mods when its working directory changes.
enum MinecraftGameDataFiles {
    static func key(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }
    static func sameLocation(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.resolvingSymlinksInPath().path == second.standardizedFileURL.resolvingSymlinksInPath().path ||
            (try? RunDirectoryCopyJournal.Identity.read(first))?.matches(second) == true
    }

    static func reservedNames(paths: LauncherPaths, instanceID: UUID) -> Set<String> {
        var names: Set<String> = [".ruri"]
        guard let version = paths.instanceRepositoryVersions?[instanceID] else { return names }
        let game = paths.game(instanceID)
        let repository = paths.directoryRoot(paths.directoryID(for: instanceID))
        if sameLocation(game, repository) {
            names.formUnion(["versions", "libraries", "assets", GameDirectory.markerName,
                             "launcher_profiles.json", "launcher_accounts.json", "launcher_msa_credentials.bin",
                             "launcher_settings.json", "launcher_log.txt", "usercache.json", "usernamecache.json",
                             ".hmcl", "hmcl.json", "hmclversion.cfg"])
        } else if sameLocation(game, paths.versionDirectory(instanceID)) {
            names.formUnion([version + ".json", version + ".jar", "libraries", ".hmcl", "hmclversion.cfg", "modpack.cfg", RepositoryImportTransaction.markerName])
        }
        return names
    }

    static func copyIssue(source: RunDirectorySnapshot, sourcePaths: LauncherPaths, targetPaths: LauncherPaths, instanceID: UUID) -> String? {
        let from = sourcePaths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath().path
        let to = targetPaths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath().path
        let repository = sourcePaths.directoryRoot(sourcePaths.directoryID(for: instanceID))
        let version = sourcePaths.versionDirectory(instanceID)
        let sourceRoot = sourcePaths.game(instanceID), targetRoot = targetPaths.game(instanceID)
        let repositoryPair = sourcePaths.instanceRepositoryVersions?[instanceID] != nil &&
            ((sameLocation(sourceRoot, repository) && sameLocation(targetRoot, version)) ||
             (sameLocation(sourceRoot, version) && sameLocation(targetRoot, repository)))
        if !repositoryPair && (from == to || from.hasPrefix(to + "/") || to.hasPrefix(from + "/")) {
            return "源目录与目标目录互相包含，无法复制。请选择互不嵌套的游戏目录。"
        }
        let reserved = Set(reservedNames(paths: targetPaths, instanceID: instanceID).map(key))
        let collisions = Set(source.game.compactMap { $0.path.split(separator: "/").first.map(String.init) }).filter { reserved.contains(key($0)) }
        if !collisions.isEmpty {
            return "当前游戏内容包含目标位置保留的文件或目录：\(collisions.sorted().joined(separator: "、"))。请选择其他目标，以保留这些内容和原有安装文件。"
        }
        return nil
    }
}
