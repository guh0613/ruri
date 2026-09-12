import RuriLocalization
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
            let labels = [("saves", Messages.CoreMinecraftGameLocations.worlds.localized), ("mods", Messages.CoreMinecraftGameLocations.mods.localized), ("config", Messages.CoreMinecraftGameLocations.modConfigs.localized), ("resourcepacks", Messages.CoreMinecraftGameLocations.resourcePacks.localized), ("shaderpacks", Messages.CoreMinecraftGameLocations.shaders.localized), ("options.txt", Messages.CoreMinecraftGameLocations.gameSettings.localized)]
            let contents = available ? labels.compactMap { FileManager.default.fileExists(atPath: url.appendingPathComponent($0.0).path) ? $0.1 : nil } : []
            return .init(directory: url, title: title, explanation: explanation, available: available, contents: contents)
        }
        values.append(try location(root, title: Messages.CoreMinecraftGameLocations.sharedGameDirectory.localized, explanation: Messages.CoreMinecraftGameLocations.sharedDirectoryContents.localized))
        values.append(try location(directory, title: Messages.CoreMinecraftGameLocations.versionDirectory.localized, explanation: Messages.CoreMinecraftGameLocations.versionDirectoryContents.localized))
        func custom(_ value: String, title: String) throws -> URL? {
            guard value.hasPrefix("/"), !value.contains("\0"), value.utf8.count <= 4_096 else { return nil }
            let url = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            if !values.contains(where: { $0.directory == url }) {
                values.append(try location(url, title: title, explanation: Messages.CoreMinecraftGameLocations.launcherGameData.localized))
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
                    else if let url = try custom(value, title: Messages.CoreMinecraftGameLocations.hmclCustomDirectory.localized) { configured = [url] }
                    else { warnings.append(Messages.CoreMinecraftGameLocations.hmclCustomDirectoryWarning.localized) }
                } else { warnings.append(Messages.CoreMinecraftGameLocations.hmclGlobalDirectoryWarning.localized) }
            } else if let settings = try optionalObject(legacyFile) {
                if (settings["usesGlobal"] as? Bool) == true { warnings.append(Messages.CoreMinecraftGameLocations.hmclGlobalSettings.localized) }
                else {
                    let type: String
                    if let name = settings["gameDirType"] as? String { type = name }
                    else if let index = settings["gameDirType"] as? Int, (0...2).contains(index) { type = ["ROOT_FOLDER", "VERSION_FOLDER", "CUSTOM"][index] }
                    else { type = "UNKNOWN" }
                    switch type {
                    case "ROOT_FOLDER": configured = [root]
                    case "VERSION_FOLDER": configured = [directory]
                    case "CUSTOM":
                        if let path = settings["gameDir"] as? String, let url = try custom(path, title: Messages.CoreMinecraftGameLocations.hmclCustomDirectory.localized) { configured = [url] }
                        else { warnings.append(Messages.CoreMinecraftGameLocations.hmclCustomDirectoryMissing.localized) }
                    default: warnings.append(Messages.CoreMinecraftGameLocations.hmclDirectoryPolicyUnreadable.localized)
                    }
                }
            } else if let profiles = try optionalObject(root.appendingPathComponent("launcher_profiles.json"))?["profiles"] as? [String: [String: Any]] {
                guard profiles.count <= 2_000 else { throw RuriError.message(Messages.CoreMinecraftGameLocations.profilesLimit) }
                for (_, profile) in profiles.sorted(by: { $0.key < $1.key }) where (profile["lastVersionId"] as? String) == version {
                    if let value = profile["gameDir"] as? String, !value.isEmpty {
                        if let url = try custom(value, title: Messages.CoreMinecraftGameLocations.officialCustomDirectory.localized) { configured.append(url) }
                        else { warnings.append(Messages.CoreMinecraftGameLocations.officialDirectoryMissing.localized) }
                    } else { configured.append(root) }
                }
            }
        }
        if !exists(modpackFile) { documents.append(.init(url: modpackFile, data: nil)) }
        let unique = Set(configured.map { $0.path })
        let suggested = unique.count == 1 && warnings.isEmpty ? unique.first : nil
        if unique.count > 1 { warnings.append(Messages.CoreMinecraftGameLocations.multipleLauncherProfiles.localized) }
        if suggested == nil && warnings.isEmpty { warnings.append(Messages.CoreMinecraftGameLocations.noRunDirectory.localized) }
        return .init(values: values, suggested: suggested, warnings: warnings)
    }
}
