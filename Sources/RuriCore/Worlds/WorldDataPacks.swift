import RuriLocalization
import Foundation
import ZIPFoundation
import Darwin

public struct WorldDataPack: Identifiable, Sendable {
    public var id: String { url.lastPathComponent }
    public let url: URL
    public let enabled: Bool
    public let description: String
    public let format: String?
    public let error: String?
}

public struct WorldDataPackPriority: Equatable, Sendable {
    /// Highest priority first. Built-in and missing entries retain relative order.
    public let keys: [String]
    public let localKeys: Set<String>
    let storedKeys: [String]
    let disabledKeys: [String]
}

private struct WorldPackSelection {
    let file: URL
    let original: Data
    var enabled: [String]
    var disabled: [String]

    init(world: URL) throws {
        file = world.appendingPathComponent("level.dat")
        do { original = try RunDirectoryCopyGuard.read(file, limit: 32 * 1024 * 1024) }
        catch { throw RuriError.message(Messages.CoreWorldDataPacks.disabledText1) }
        var reader = try NBTReader(data: original)
        guard case .compound(let root)? = try reader.read()["Data"] else { throw RuriError.message(Messages.CoreWorldDataPacks.rootText1) }
        if let packs = root["DataPacks"], case .compound = packs {} else if root["DataPacks"] != nil { throw RuriError.message(Messages.CoreWorldDataPacks.packsText1) }
        func strings(_ value: NBTValue?, fallback: [String]) throws -> [String] {
            guard let value else { return fallback }
            guard case .list(let items) = value, items.count <= 4096, items.allSatisfy({ $0.string != nil }) else { throw RuriError.message(Messages.CoreWorldDataPacks.itemsText1) }
            return items.compactMap(\.string)
        }
        enabled = try strings(root["DataPacks"]?["Enabled"], fallback: ["vanilla"])
        disabled = try strings(root["DataPacks"]?["Disabled"], fallback: [])
    }
    mutating func select(_ key: String, enabled value: Bool?) {
        // Preserve priority of existing packs; a newly enabled pack goes last.
        if value != true { enabled.removeAll { $0 == key } }
        if value != false { disabled.removeAll { $0 == key } }
        if value == true && !enabled.contains(key) { enabled.append(key) }
        if value == false && !disabled.contains(key) { disabled.append(key) }
    }
    func save(backup: URL) throws {
        let updated = try NBTReader.updatingDataPacks(original, enabled: enabled, disabled: disabled)
        guard try RunDirectoryCopyGuard.read(file, limit: 32 * 1024 * 1024) == original else { throw RuriError.message(Messages.CoreWorldDataPacks.updatedText1) }
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: backup, options: .atomic)
        try updated.write(to: file, options: .atomic)
    }
}

extension WorldManager {
    public func dataPackBackup(folder: String) throws -> URL {
        _ = try worldURL(folder)
        return try LauncherPaths.safePath("world-datapack-backups/\(folder)/level.dat", within: paths.gameDataState(instanceID))
    }
    public func dataPacks(folder: String) throws -> [WorldDataPack] {
        try withDataPacks(folder) { directory, selection in try Self.readDataPacks(directory: directory, selection: selection) }
    }
    private static func readDataPacks(directory: URL, selection: WorldPackSelection) throws -> [WorldDataPack] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).compactMap { url in
            let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true, info.isDirectory == true || (info.isRegularFile == true && (url.lastPathComponent.lowercased().hasSuffix(".zip") || url.lastPathComponent.lowercased().hasSuffix(".zip.disabled"))) else { return nil }
            let key = Self.packKey(url)
            let physicallyDisabled = info.isDirectory == true ? !FileManager.default.fileExists(atPath: url.appendingPathComponent("pack.mcmeta").path) : url.pathExtension == "disabled"
            do {
                let meta = try Self.packMetadata(url)
                return WorldDataPack(url: url, enabled: !physicallyDisabled && !selection.disabled.contains(key), description: meta.0, format: meta.1, error: nil)
            } catch {
                return WorldDataPack(url: url, enabled: false, description: "", format: nil, error: error.localizedDescription)
            }
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
    public func dataPackPriority(folder: String) throws -> WorldDataPackPriority {
        try withDataPacks(folder) { directory, selection in
            try Self.priority(directory: directory, selection: selection)
        }
    }
    private static func priority(directory: URL, selection: WorldPackSelection) throws -> WorldDataPackPriority {
        let packs = try readDataPacks(directory: directory, selection: selection)
        let local = packs.filter { $0.enabled && $0.error == nil }.map { Self.packKey($0.url) }
        var known = Set<String>()
        let enabled = (selection.enabled + local).filter { known.insert($0).inserted }
        return WorldDataPackPriority(keys: enabled.reversed(), localKeys: Set(local), storedKeys: selection.enabled, disabledKeys: selection.disabled)
    }
    public func setDataPackPriority(_ keys: [String], folder: String, expecting previous: WorldDataPackPriority) throws {
        try withDataPacks(folder) { directory, selection in
            let current = try Self.priority(directory: directory, selection: selection)
            guard current == previous else { throw RuriError.message(Messages.CoreWorldDataPacks.currentText1) }
            guard keys.count == current.keys.count, Set(keys) == Set(current.keys) else { throw RuriError.message(Messages.CoreWorldDataPacks.currentText2) }
            guard keys.filter({ !current.localKeys.contains($0) }) == current.keys.filter({ !current.localKeys.contains($0) }) else {
                throw RuriError.message(Messages.CoreWorldDataPacks.currentText3)
            }
            selection.enabled = keys.reversed()
            guard selection.enabled != previous.storedKeys else { return }
            try selection.save(backup: dataPackBackup(folder: folder))
        }
    }
    public func setDataPackEnabled(_ enabled: Bool, name: String, folder: String) throws {
        try withDataPacks(folder) { directory, selection in
            let pack = try Self.packURL(name, directory: directory)
            _ = try Self.packMetadata(pack)
            let isDirectory = try pack.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if !isDirectory, Self.exists(Self.alternateZIP(pack)) { throw RuriError.message(Messages.CoreWorldDataPacks.isDirectoryText1(String(describing: name))) }
            // Accept HMCL's disabled ZIPs and renamed folder metadata too.
            let source = isDirectory ? pack.appendingPathComponent("pack.mcmeta.disabled") : pack
            let destination = isDirectory ? pack.appendingPathComponent("pack.mcmeta") : pack.deletingPathExtension()
            let needsRename = enabled && (isDirectory ? !FileManager.default.fileExists(atPath: destination.path) : pack.pathExtension == "disabled")
            if needsRename {
                guard !Self.exists(destination) else { throw RuriError.message(Messages.CoreWorldDataPacks.needsRenameText1(String(describing: destination.lastPathComponent))) }
                try FileManager.default.moveItem(at: source, to: destination)
            }
            do {
                selection.select(Self.packKey(pack), enabled: enabled)
                try selection.save(backup: dataPackBackup(folder: folder))
            } catch {
                if needsRename { try FileManager.default.moveItem(at: destination, to: source) }
                throw error
            }
        }
    }
    public func importDataPack(from source: URL, folder: String) throws {
        try importDataPacks(from: [source], folder: folder)
    }
    public func importDataPacks(from sources: [URL], folder: String) throws {
        guard !sources.isEmpty, sources.count <= 200 else { throw RuriError.message(Messages.CoreWorldDataPacks.importDataPacksText1) }
        try withDataPacks(folder) { directory, selection in
            var targets: [URL] = [], names = Set<String>()
            for source in sources {
                _ = try Self.packMetadata(source)
                let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                guard isDirectory || source.pathExtension.lowercased() == "zip" else { throw RuriError.message(Messages.CoreWorldDataPacks.isDirectoryText2) }
                guard source.pathExtension != "disabled", !isDirectory || Self.exists(source.appendingPathComponent("pack.mcmeta")) else { throw RuriError.message(Messages.CoreWorldDataPacks.isDirectoryText3) }
                let target = try Self.packURL(source.lastPathComponent, directory: directory)
                guard names.insert(target.lastPathComponent.lowercased()).inserted, !Self.exists(target), !Self.exists(target.appendingPathExtension("disabled")) else {
                    throw RuriError.message(Messages.CoreWorldDataPacks.targetText1(String(describing: source.lastPathComponent)))
                }
                targets.append(target)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let staging = directory.appendingPathComponent(".ruri-import-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            for (source, target) in zip(sources, targets) {
                let staged = staging.appendingPathComponent(target.lastPathComponent)
                if try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try FileTree.copy(from: source, to: staged) }
                else { try FileManager.default.copyItem(at: source, to: staged) }
                _ = try Self.packMetadata(staged)
            }
            try Task.checkCancellation()
            var published: [URL] = []
            do {
                for target in targets {
                    try FileManager.default.moveItem(at: staging.appendingPathComponent(target.lastPathComponent), to: target)
                    published.append(target); selection.select(Self.packKey(target), enabled: true)
                }
                try selection.save(backup: dataPackBackup(folder: folder))
            } catch {
                for target in published { try FileManager.default.removeItem(at: target) }
                throw error
            }
        }
    }
    @discardableResult public func removeDataPack(name: String, folder: String) throws -> URL? {
        try withDataPacks(folder) { directory, selection in
            let target = try Self.packURL(name, directory: directory)
            guard Self.exists(target) else { throw RuriError.message(Messages.CoreWorldDataPacks.targetText2) }
            let isDirectory = try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory || !Self.exists(Self.alternateZIP(target)) { selection.select(Self.packKey(target), enabled: nil) }
            try selection.save(backup: dataPackBackup(folder: folder))
            do {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: target, resultingItemURL: &trashed)
                return trashed as URL?
            } catch { try selection.original.write(to: selection.file, options: .atomic); throw error }
        }
    }
    private func withDataPacks<T>(_ folder: String, operation: (URL, inout WorldPackSelection) throws -> T) throws -> T {
        try lock(); defer { unlock() }
        try recover()
        let world = try worldURL(folder)
        let fd = try Self.readLock(world); defer { if let fd { close(fd) } }
        let directory = world.appendingPathComponent("datapacks")
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: directory.path)) == nil else { throw RuriError.message(Messages.CoreWorldDataPacks.directoryText1) }
        var selection = try WorldPackSelection(world: world)
        return try operation(directory, &selection)
    }
    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }
    private static func packURL(_ name: String, directory: URL) throws -> URL {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw RuriError.message(Messages.CoreWorldDataPacks.packURLText1) }
        let url = directory.appendingPathComponent(name)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw RuriError.message(Messages.CoreWorldDataPacks.urlText1) }
        return try LauncherPaths.safePath(name, within: directory)
    }
    private static func packKey(_ url: URL) -> String {
        let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        return "file/" + (!directory && url.pathExtension == "disabled" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent)
    }
    private static func alternateZIP(_ url: URL) -> URL { url.pathExtension == "disabled" ? url.deletingPathExtension() : url.appendingPathExtension("disabled") }
    private static func packMetadata(_ url: URL) throws -> (String, String?) {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isSymbolicLink != true else { throw RuriError.message(Messages.CoreWorldDataPacks.infoText1) }
        let data: Data
        if info.isDirectory == true {
            let metadata = url.appendingPathComponent("pack.mcmeta")
            do { data = try RunDirectoryCopyGuard.read(Self.exists(metadata) ? metadata : url.appendingPathComponent("pack.mcmeta.disabled"), limit: 1024 * 1024) }
            catch { throw RuriError.message(Messages.CoreWorldDataPacks.metadataText1) }
        } else {
            guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 512 * 1024 * 1024 else { throw RuriError.message(Messages.CoreWorldDataPacks.metadataText2) }
            let archive = try Archive(url: url, accessMode: .read)
            guard let entry = archive["pack.mcmeta"], entry.type == .file, entry.uncompressedSize <= 1024 * 1024 else { throw RuriError.message(Messages.CoreWorldDataPacks.entryText1) }
            var contents = Data()
            let checksum = try archive.extract(entry) { chunk in
                guard chunk.count <= 1024 * 1024 - contents.count else { throw RuriError.message(Messages.CoreWorldDataPacks.checksumText1) }
                contents += chunk
            }
            guard checksum == entry.checksum else { throw RuriError.message(Messages.CoreWorldDataPacks.checksumText2) }
            data = contents
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let pack = root["pack"] as? [String: Any], pack["description"] != nil else { throw RuriError.message(Messages.CoreWorldDataPacks.packText1) }
        func description(_ value: Any) -> String {
            if let text = value as? String { return text }
            if let list = value as? [Any] { return list.map(description).joined() }
            if let object = value as? [String: Any] { return (object["text"] as? String ?? object["translate"] as? String ?? "") + (object["extra"].map(description) ?? "") }
            return ""
        }
        func format(_ value: Any?) -> String? {
            if let number = value as? Int { return String(number) }
            if let numbers = value as? [Int] { return numbers.map(String.init).joined(separator: ".") }
            return nil
        }
        let range = format(pack["min_format"]).map { "\($0)–\(format(pack["max_format"]) ?? "?")" }
        return (String(description(pack["description"]!).prefix(2000)), range ?? format(pack["pack_format"]))
    }
}
