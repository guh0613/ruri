import RuriLocalization
import Foundation
import ZIPFoundation
import Darwin

public struct WorldSnapshot: Identifiable, Sendable {
    public var id: String { folder }
    public let folder: String
    public let url: URL
    public let name: String
    public let version: String?
    public let gameType: Int?
    public let hardcore: Bool
    public var gameMode: String? {
        if hardcore { return Messages.CoreWorldManager.hardcoreMode.localized }
        return gameType.flatMap { [0: Messages.CoreWorldManager.survivalMode, 1: Messages.CoreWorldManager.creativeMode,
                                  2: Messages.CoreWorldManager.adventureMode, 3: Messages.CoreWorldManager.spectatorMode][$0]?.localized }
    }
    public let lastPlayed: Date?
    public let size: Int64?
    public let icon: URL?
    public let metadataError: String?
}
public struct WorldBackupMetadata: Codable, Sendable {
    public var formatVersion = 1
    public let worldFolder: String
    public let worldName: String
    public let gameVersion: String?
    public let createdAt: Date
    public let reason: String
    public var reasonMessage: LocalizedMessage? = nil
    public var displayReason: String { reasonMessage?.localized ?? reason }
}
public struct WorldBackup: Identifiable, Sendable {
    public var id: String { url.lastPathComponent }
    public let url: URL
    public let metadata: WorldBackupMetadata?
    public let size: Int64
    public let createdAt: Date
    public var title: String { metadata?.worldName ?? url.deletingPathExtension().lastPathComponent }
}

public actor WorldManager {
    private static let diskLock = NSRecursiveLock()
    private let operationLock = GameDataOperationLock()
    private let locationLock = InstanceLocationOperationLock()
    let paths: LauncherPaths
    let instanceID: UUID
    private var saves: URL { paths.game(instanceID).appendingPathComponent("saves") }
    public var backupDirectory: URL { paths.gameDataState(instanceID).appendingPathComponent("world-backups") }
    private var transaction: URL { paths.gameDataState(instanceID).appendingPathComponent("world-restore") }
    struct RestoreJournal: Codable { let folder: String; let hadOriginal: Bool }
    public init(paths: LauncherPaths, instanceID: UUID) { self.paths = paths; self.instanceID = instanceID }
    func lock() throws {
        Self.diskLock.lock()
        var acquired = false, located = false
        do {
            try locationLock.acquire(paths: paths, instanceID: instanceID); located = true
            try paths.validateInstanceLocation(instanceID)
            try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID)
            try operationLock.acquire(directory: paths.gameDataState(instanceID), name: ".world-operation.lock"); acquired = true
            try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID)
        } catch { if acquired { operationLock.release() }; if located { locationLock.release() }; Self.diskLock.unlock(); throw error }
    }
    func unlock() { operationLock.release(); locationLock.release(); Self.diskLock.unlock() }
    func worldURL(_ folder: String) throws -> URL {
        guard !folder.isEmpty, folder != ".", folder != "..", !folder.contains("/"), !folder.contains("\\") else { throw RuriError.message(Messages.CoreWorldManager.invalidWorldDirectoryName) }
        let target = saves.appendingPathComponent(folder)
        for url in [saves, target] where (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil { throw RuriError.message(Messages.CoreWorldManager.symlinkDirectoryUnmodified) }
        return try LauncherPaths.safePath(folder, within: saves)
    }
    public func worlds() throws -> [WorldSnapshot] {
        try lock(); defer { unlock() }
        try recover()
        guard FileManager.default.fileExists(atPath: saves.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isSymbolicLink) != true,
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  hasLevelData(entry) else { return nil }
            return snapshot(entry)
        }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }
    /// The most recently played worlds with world and backup totals, without
    /// measuring world sizes or reading backup metadata, for summaries.
    public func overview(limit: Int) throws -> (recent: [WorldSnapshot], worlds: Int, backups: Int) {
        try paths.validateInstanceLocation(instanceID)
        try lock(); defer { unlock() }
        try recover()
        let manager = FileManager.default
        let folders = !manager.fileExists(atPath: saves.path) ? [] : try manager.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).filter { entry in
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isSymbolicLink != true && values?.isDirectory == true && hasLevelData(entry)
        }
        let recent = folders.map { snapshot($0, measuringSize: false) }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }.prefix(limit)
        let backups = !manager.fileExists(atPath: backupDirectory.path) ? 0 : try manager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return url.pathExtension == "zip" && values?.isRegularFile == true && values?.isSymbolicLink != true
        }.count
        return (Array(recent), folders.count, backups)
    }
    public func backups() throws -> [WorldBackup] {
        try paths.validateInstanceLocation(instanceID)
        try lock(); defer { unlock() }
        guard FileManager.default.fileExists(atPath: backupDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).compactMap { url in
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard url.pathExtension == "zip", info.isRegularFile == true, info.isSymbolicLink != true else { return nil }
            let metadata = try? readMetadata(url)
            return WorldBackup(url: url, metadata: metadata, size: Int64(info.fileSize ?? 0), createdAt: metadata?.createdAt ?? info.contentModificationDate ?? .distantPast)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    public func backup(folder: String, reason: String? = nil, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> WorldBackup {
        try lock(); defer { unlock() }
        try recover()
        let world = try worldURL(folder)
        guard hasLevelData(world) else { throw RuriError.message(Messages.CoreWorldManager.levelDataMissing) }
        let lock = try Self.readLock(world); defer { if let lock { close(lock) } }
        return try writeBackup(world, reason: reason.map(LocalizedMessage.verbatim) ?? Messages.CoreWorldManager.manualBackup, progress: progress)
    }
    private func writeBackup(_ world: URL, reason: LocalizedMessage, progress: @Sendable (Int, Int) -> Void) throws -> WorldBackup {
        let info = snapshot(world)
        let metadata = WorldBackupMetadata(worldFolder: world.lastPathComponent, worldName: info.name, gameVersion: info.version, createdAt: Date(), reason: reason.localized, reasonMessage: reason.recorded())
        let name = ISO8601DateFormatter().string(from: metadata.createdAt).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString + ".zip"
        let destination = backupDirectory.appendingPathComponent(name)
        try SafeArchive.create(from: world, to: destination, prefix: "world", additionalFiles: ["ruri-world-backup.json": try JSONEncoder().encode(metadata)], excluding: ["session.lock"], progress: progress)
        return WorldBackup(url: destination, metadata: metadata, size: Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), createdAt: metadata.createdAt)
    }
    public func restore(_ backup: WorldBackup, replaceExisting: Bool = false, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> String {
        try lock(); defer { unlock() }
        try recover()
        let metadata = try readMetadata(backup.url)
        let unpacked = transaction.appendingPathComponent("unpacked")
        do {
            try SafeArchive.extract(backup.url, to: unpacked, maxBytes: 128 * 1024 * 1024 * 1024)
            let source = unpacked.appendingPathComponent("world")
            guard hasLevelData(source) else { throw RuriError.message(Messages.CoreWorldManager.backupDataMissing) }
            let folder = replaceExisting ? metadata.worldFolder : try uniqueFolder(Messages.CoreWorldManager.restoredFolder(metadata.worldFolder).localized)
            let destination = try worldURL(folder)
            let exists = FileManager.default.fileExists(atPath: destination.path)
            let lock = exists ? try Self.readLock(destination) : nil
            defer { if let lock { close(lock) } }
            if exists { _ = try writeBackup(destination, reason: Messages.CoreWorldManager.automaticBackup, progress: progress) }
            try FileManager.default.moveItem(at: source, to: transaction.appendingPathComponent("incoming"))
            let journal = RestoreJournal(folder: folder, hadOriginal: exists)
            try JSONEncoder().encode(journal).write(to: transaction.appendingPathComponent("journal.json"), options: .atomic)
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
            if exists { try FileManager.default.moveItem(at: destination, to: transaction.appendingPathComponent("previous")) }
            try FileManager.default.moveItem(at: transaction.appendingPathComponent("incoming"), to: destination)
            try recover()
            return folder
        } catch {
            do { try recover() } catch { throw RuriError.message(Messages.CoreWorldManager.restoreNeedsReview(transaction.path, error.localizedDescription)) }
            throw error
        }
    }
    public func recover() throws {
        if FileManager.default.fileExists(atPath: transaction.path) { try OperationReadPolicy.requireRecoveryPermission(paths: paths, kind: "world", instanceID: instanceID) }
        try paths.validateInstanceLocation(instanceID)
        try lock(); defer { unlock() }
        let fm = FileManager.default
        guard fm.fileExists(atPath: transaction.path) else { return }
        let journalURL = transaction.appendingPathComponent("journal.json")
        guard fm.fileExists(atPath: journalURL.path) else { try fm.removeItem(at: transaction); return }
        let journal = try JSONDecoder().decode(RestoreJournal.self, from: Data(contentsOf: journalURL))
        let target = try worldURL(journal.folder)
        let previous = transaction.appendingPathComponent("previous")
        let incoming = transaction.appendingPathComponent("incoming")
        let hasTarget = fm.fileExists(atPath: target.path), hasPrevious = fm.fileExists(atPath: previous.path), hasIncoming = fm.fileExists(atPath: incoming.path)
        if hasPrevious && !hasTarget {
            try fm.createDirectory(at: saves, withIntermediateDirectories: true)
            try fm.moveItem(at: previous, to: target)
        } else if hasPrevious && hasTarget && hasIncoming {
            throw RuriError.message(Messages.CoreWorldManager.restoreDirectoryConflict)
        } else if journal.hadOriginal && !hasPrevious && !hasTarget {
            throw RuriError.message(Messages.CoreWorldManager.originalWorldMissing)
        }
        // The only write to the saves directory is a complete-directory rename.
        // A present target and absent incoming mean the replacement committed.
        try fm.removeItem(at: transaction)
    }
    public func importWorld(from source: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> String {
        try lock(); defer { unlock() }
        try recover()
        let temporary = paths.instance(instanceID).appendingPathComponent("world-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root: URL
        if source.pathExtension.lowercased() == "zip" {
            root = temporary.appendingPathComponent("unpacked")
            try SafeArchive.extract(source, to: root, maxBytes: 128 * 1024 * 1024 * 1024)
        } else { root = source }
        let world: URL
        if hasLevelData(root) { world = root }
        else {
            let candidates = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter(hasLevelData)
            guard candidates.count == 1, let candidate = candidates.first else { throw RuriError.message(Messages.CoreWorldManager.invalidWorldFolder) }
            world = candidate
        }
        let lock = try Self.readLock(world); defer { if let lock { close(lock) } }
        let incoming = temporary.appendingPathComponent("incoming")
        try FileTree.copy(from: world, to: incoming, excluding: ["session.lock"], progress: progress)
        let name = try uniqueFolder(snapshot(world).name)
        let target = try worldURL(name)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Task.checkCancellation(); try FileManager.default.moveItem(at: incoming, to: target)
        return name
    }
    public func exportWorld(folder: String, to destination: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws {
        try lock(); defer { unlock() }
        try recover()
        let world = try worldURL(folder)
        guard hasLevelData(world) else { throw RuriError.message(Messages.CoreWorldManager.worldMissing) }
        let lock = try Self.readLock(world); defer { if let lock { close(lock) } }
        try SafeArchive.create(from: world, to: destination, excluding: ["session.lock"], progress: progress)
    }
    public func removeWorld(folder: String) throws {
        try lock(); defer { unlock() }
        try recover()
        let world = try worldURL(folder)
        let lock = try Self.readLock(world); defer { if let lock { close(lock) } }
        try FileManager.default.trashItem(at: world, resultingItemURL: nil)
    }
    public func removeBackup(_ backup: WorldBackup) throws {
        try lock(); defer { unlock() }
        let file = try LauncherPaths.safePath(backup.url.lastPathComponent, within: backupDirectory)
        guard file.standardizedFileURL == backup.url.standardizedFileURL else { throw RuriError.message(Messages.CoreWorldManager.backupWrongInstance) }
        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
    }
    private func uniqueFolder(_ suggested: String) throws -> String {
        let value = suggested.components(separatedBy: CharacterSet(charactersIn: "/\\:\0")).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = value.isEmpty || value == "." || value == ".." ? Messages.CoreWorldManager.importedWorld.localized : String(value.prefix(80))
        for index in 0..<10_000 {
            let name = index == 0 ? base : "\(base) \(index + 1)"
            if !FileManager.default.fileExists(atPath: try worldURL(name).path) { return name }
        }
        throw RuriError.message(Messages.CoreWorldManager.uniqueWorldDirectory)
    }
    private func readMetadata(_ file: URL) throws -> WorldBackupMetadata {
        let archive = try Archive(url: file, accessMode: .read)
        guard let entry = archive["ruri-world-backup.json"], entry.uncompressedSize < 64 * 1024 else { throw RuriError.message(Messages.CoreWorldManager.invalidBackup) }
        var data = Data(); let checksum = try archive.extract(entry) { data.append($0) }
        guard checksum == entry.checksum else { throw RuriError.message(Messages.CoreWorldManager.checksumFailed) }
        let result = try JSONDecoder().decode(WorldBackupMetadata.self, from: data)
        guard result.formatVersion == 1 else { throw RuriError.message(Messages.CoreWorldManager.unsupportedBackupVersion) }; return result
    }
    private func hasLevelData(_ directory: URL) -> Bool {
        ["level.dat", "level.dat_old"].contains {
            guard let values = try? directory.appendingPathComponent($0).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }
    private func snapshot(_ world: URL, measuringSize: Bool = true) -> WorldSnapshot {
        var data: NBTValue?; var failure: String?
        do {
            let file = FileManager.default.fileExists(atPath: world.appendingPathComponent("level.dat").path) ? world.appendingPathComponent("level.dat") : world.appendingPathComponent("level.dat_old")
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreWorldManager.nbtTooLarge) }
            var reader = try NBTReader(data: Data(contentsOf: file)); data = try reader.read()["Data"]
        } catch { failure = Messages.CoreWorldManager.worldInfoReadFailed.localized }
        let lastPlayed = data?["LastPlayed"]?.integer.flatMap { (0..<253402300800000).contains($0) ? Date(timeIntervalSince1970: Double($0) / 1000) : nil }
        let icon = world.appendingPathComponent("icon.png")
        let entries = measuringSize ? try? FileTree.entries(in: world) : nil
        return WorldSnapshot(folder: world.lastPathComponent, url: world, name: data?["LevelName"]?.string ?? world.lastPathComponent, version: data?["Version"]?["Name"]?.string, gameType: data?["GameType"]?.integer.flatMap(Int.init(exactly:)), hardcore: data?["hardcore"]?.integer == 1, lastPlayed: lastPlayed, size: entries.map { $0.filter { !$0.directory }.reduce(0) { $0 + $1.size } }, icon: FileManager.default.fileExists(atPath: icon.path) ? icon : nil, metadataError: failure)
    }
    nonisolated static func readLock(_ world: URL) throws -> Int32? {
        let file = world.appendingPathComponent("session.lock")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let fd = open(file.path, O_RDONLY)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreWorldManager.lockReadFailed) }
        var lock = flock(); lock.l_type = Int16(F_RDLCK); lock.l_whence = Int16(SEEK_SET); lock.l_start = 0; lock.l_len = 0
        guard fcntl(fd, F_SETLK, &lock) != -1 else { close(fd); throw RuriError.message(Messages.CoreWorldManager.worldInUse) }
        return fd
    }
}
