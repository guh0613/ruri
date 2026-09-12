import RuriLocalization
import Foundation
import ZIPFoundation

public enum ContentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case mod, resourcepack, shader
    public var id: String { rawValue }
    public var title: String { switch self { case .mod: Messages.CoreContentManager.titleText1.localized; case .resourcepack: Messages.CoreContentManager.titleText2.localized; case .shader: Messages.CoreContentManager.titleText3.localized } }
    public var folder: String { switch self { case .mod: "mods"; case .resourcepack: "resourcepacks"; case .shader: "shaderpacks" } }
    public var fileExtension: String { self == .mod ? "jar" : "zip" }
    public var fileExtensions: [String] { self == .mod ? ["jar", "litemod"] : ["zip"] }
}

public struct ManagedContent: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(kind.rawValue):\(provider):\(projectID)" }
    public var provider: String
    public var projectID: String
    public var versionID: String
    public var title: String
    public var versionName: String
    public var publishedAt: String?
    public var kind: ContentKind
    public var filename: String
    public var sha1: String?
    public var sha512: String?
    public var md5: String?
    public var size: Int64
    public var requiredProjects: [String]
    public var enabled: Bool
    public var relativePath: String { "\(kind.folder)/\(filename)\(enabled ? "" : ".disabled")" }
    public init(provider: String = "modrinth", projectID: String, versionID: String, title: String, versionName: String, publishedAt: String? = nil, kind: ContentKind, filename: String, sha1: String? = nil, sha512: String? = nil, md5: String? = nil, size: Int64, requiredProjects: [String] = [], enabled: Bool = true) {
        self.provider = provider; self.projectID = projectID; self.versionID = versionID; self.title = title
        self.versionName = versionName; self.publishedAt = publishedAt; self.kind = kind; self.filename = filename
        self.sha1 = sha1; self.sha512 = sha512; self.md5 = md5; self.size = size; self.requiredProjects = requiredProjects; self.enabled = enabled
    }
}

public struct LocalContentFile: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let filename: String
    public let title: String
    public let version: String?
    public let modID: String?
    public let kind: ContentKind
    public let enabled: Bool
    public let size: Int64
    public let managed: ManagedContent?
}
public struct ContentInstallation: Sendable {
    public var record: ManagedContent
    public let source: URL
    public init(record: ManagedContent, source: URL) { self.record = record; self.source = source }
}

/// Owns per-instance content metadata and a disk journal. A process interruption
/// during replacement is rolled back before the next scan, install or launch.
public actor ContentManager {
    // Multiple views and services may create managers for the same instance.
    // Journal recovery must never race a live commit from another manager.
    private static let diskLock = NSRecursiveLock()
    private let operationLock = GameDataOperationLock()
    private let locationLock = InstanceLocationOperationLock()
    let paths: LauncherPaths
    let instanceID: UUID
    var root: URL { paths.game(instanceID) }
    var recordsURL: URL { paths.gameDataState(instanceID).appendingPathComponent("content.json") }
    var transactionURL: URL { paths.gameDataState(instanceID).appendingPathComponent("content-transaction") }
    public init(paths: LauncherPaths, instanceID: UUID) { self.paths = paths; self.instanceID = instanceID }
    func lock() throws {
        Self.diskLock.lock()
        var acquired = false, located = false
        do {
            try locationLock.acquire(paths: paths, instanceID: instanceID); located = true
            try paths.validateInstanceLocation(instanceID)
            try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID)
            try operationLock.acquire(directory: paths.gameDataState(instanceID), name: ".content-operation.lock"); acquired = true
            try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID)
        } catch { if acquired { operationLock.release() }; if located { locationLock.release() }; Self.diskLock.unlock(); throw error }
    }
    func unlock() { operationLock.release(); locationLock.release(); Self.diskLock.unlock() }
    struct Journal: Codable {
        let affected: [String]
        let originals: [String]
        let oldRecords: [ManagedContent]
    }
    func contentURL(_ path: String) throws -> URL {
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, ContentKind.allCases.contains(where: { $0.folder == pieces[0] }) else { throw RuriError.message(Messages.CoreContentManager.piecesText1(String(describing: path))) }
        let directory = root.appendingPathComponent(String(pieces[0]))
        let target = directory.appendingPathComponent(String(pieces[1]))
        for url in [directory, target] where (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw RuriError.message(Messages.CoreContentManager.targetText1(String(describing: url.lastPathComponent)))
        }
        return try LauncherPaths.safePath(String(pieces[1]), within: directory)
    }
    public func records() throws -> [ManagedContent] {
        try lock(); defer { unlock() }
        try recover()
        return try readRecords()
    }
    func readRecords() throws -> [ManagedContent] {
        guard FileManager.default.fileExists(atPath: recordsURL.path) else { return [] }
        return try JSONDecoder().decode([ManagedContent].self, from: Data(contentsOf: recordsURL)).map { record in
            var record = record
            let expected = try contentURL(record.relativePath)
            if !FileManager.default.fileExists(atPath: expected.path) {
                record.enabled.toggle()
                let alternate = try contentURL(record.relativePath)
                if !FileManager.default.fileExists(atPath: alternate.path) { record.enabled.toggle() }
            }
            return record
        }
    }
    func writeRecords(_ records: [ManagedContent]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: recordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: recordsURL, options: .atomic)
    }
    public func recover() throws {
        try paths.validateInstanceLocation(instanceID)
        try lock(); defer { unlock() }
        let fm = FileManager.default
        guard fm.fileExists(atPath: transactionURL.path) else { return }
        let journalURL = transactionURL.appendingPathComponent("journal.json")
        if fm.fileExists(atPath: transactionURL.appendingPathComponent("committed").path) || !fm.fileExists(atPath: journalURL.path) {
            try fm.removeItem(at: transactionURL); return
        }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        for path in journal.originals {
            let backup = try LauncherPaths.safePath(path, within: transactionURL.appendingPathComponent("backups"))
            guard journal.affected.contains(path), (try? fm.attributesOfItem(atPath: backup.path)[.type]) as? FileAttributeType == .typeRegular else { throw RuriError.message(Messages.CoreContentManager.backupText1(String(describing: path), String(describing: transactionURL.path))) }
        }
        // Backups remain in place throughout recovery so another interrupted
        // recovery can safely repeat the same operation.
        for path in journal.affected {
            let destination = try contentURL(path)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            if journal.originals.contains(path) {
                let backup = try LauncherPaths.safePath(path, within: transactionURL.appendingPathComponent("backups"))
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: backup, to: destination)
            }
        }
        try writeRecords(journal.oldRecords)
        try fm.removeItem(at: transactionURL)
    }
    public func install(_ incoming: [ContentInstallation], expecting expectedRecords: [ManagedContent]? = nil) throws {
        try lock(); defer { unlock() }
        try recover(); try Task.checkCancellation()
        let fm = FileManager.default
        let oldRecords = try readRecords()
        if let expectedRecords {
            for item in incoming {
                let expected = expectedRecords.first { $0.id == item.record.id }
                let actual = oldRecords.first { $0.id == item.record.id }
                let present = try actual.map { FileManager.default.fileExists(atPath: try contentURL($0.relativePath).path) } ?? true
                guard actual == expected, present else {
                    throw RuriError.message(Messages.CoreContentManager.presentText1(String(describing: item.record.title)))
                }
            }
        }
        var installs = incoming
        guard Set(installs.map { $0.record.id }).count == installs.count else { throw RuriError.message(Messages.CoreContentManager.installsText1) }
        // Preserve a user's disabled state when updating a project.
        for i in installs.indices {
            if let old = oldRecords.first(where: { $0.id == installs[i].record.id }) { installs[i].record.enabled = old.enabled }
            let record = installs[i].record
            guard !record.filename.contains("/"), !record.filename.contains("\\"), record.kind.fileExtensions.contains(URL(fileURLWithPath: record.filename).pathExtension.lowercased()) else { throw RuriError.message(Messages.CoreContentManager.recordText1(String(describing: record.filename))) }
            let check = DownloadItem(url: nil, destination: installs[i].source, sha1: record.sha1, sha512: record.sha512, md5: record.md5, size: record.size)
            guard DownloadManager.valid(installs[i].source, item: check) else { throw RuriError.message(Messages.CoreContentManager.checkText1(String(describing: record.filename))) }
        }
        let newPaths = installs.map { $0.record.relativePath }
        guard Set(newPaths).count == newPaths.count else { throw RuriError.message(Messages.CoreContentManager.newPathsText1) }
        let incomingIDs = Set(installs.map { $0.record.id })
        let futureRecords = oldRecords.filter { !incomingIDs.contains($0.id) } + installs.map(\.record)
        for record in installs.map(\.record) where record.enabled {
            let unavailable = record.requiredProjects.filter { required in
                !futureRecords.contains { candidate in
                    guard candidate.provider == record.provider, candidate.projectID == required, candidate.enabled else { return false }
                    if incomingIDs.contains(candidate.id) { return true }
                    guard let url = try? contentURL(candidate.relativePath) else { return false }
                    return FileManager.default.fileExists(atPath: url.path)
                }
            }
            guard unavailable.isEmpty else { throw RuriError.message(Messages.CoreContentManager.urlText1(String(describing: record.title))) }
        }
        let replaced = oldRecords.filter { incomingIDs.contains($0.id) }
        for old in replaced {
            let file = try contentURL(old.relativePath)
            if fm.fileExists(atPath: file.path) {
                let check = DownloadItem(url: nil, destination: file, sha1: old.sha1, sha512: old.sha512, md5: old.md5, size: old.size)
                guard DownloadManager.valid(file, item: check) else { throw RuriError.message(Messages.CoreContentManager.checkText2(String(describing: old.filename))) }
            }
        }
        let replacedPaths = Set(replaced.map(\.relativePath))
        for path in newPaths where !replacedPaths.contains(path) {
            let target = try contentURL(path)
            guard !fm.fileExists(atPath: target.path) else { throw RuriError.message(Messages.CoreContentManager.targetText2(String(describing: target.lastPathComponent))) }
        }
        let affected = Array(Set(newPaths).union(replacedPaths)).sorted()
        try changeFiles(affected: affected, oldRecords: oldRecords) {
            for path in affected {
                let file = try contentURL(path)
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            }
            for item in installs {
                let target = try contentURL(item.record.relativePath)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: item.source, to: target)
            }
            try writeRecords(oldRecords.filter { !incomingIDs.contains($0.id) } + installs.map(\.record))
        }
    }
    public func scan(_ kind: ContentKind) throws -> [LocalContentFile] {
        try lock(); defer { unlock() }
        try recover()
        let managed = try readRecords()
        let directory = root.appendingPathComponent(kind.folder)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]).compactMap { url in
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard attributes.isRegularFile == true else { return nil }
            let enabled = !url.lastPathComponent.hasSuffix(".disabled")
            let filename = enabled ? url.lastPathComponent : String(url.lastPathComponent.dropLast(9))
            guard kind.fileExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) else { return nil }
            let record = managed.first { $0.kind == kind && $0.filename == filename && $0.enabled == enabled }
            let info = kind == .mod ? Self.modInfo(url) : nil
            return LocalContentFile(url: url, filename: filename, title: info?.name ?? record?.title ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent, version: info?.version ?? record?.versionName, modID: info?.id, kind: kind, enabled: enabled, size: Int64(attributes.fileSize ?? 0), managed: record)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    public func setEnabled(_ enabled: Bool, file: LocalContentFile) throws {
        try setEnabled(enabled, files: [file])
    }
    public func importFiles(_ files: [URL], kind: ContentKind) throws {
        try lock(); defer { unlock() }
        var plans: [ContentInstallation] = []
        let existing = try scan(kind)
        var importedIDs = Set<String>()
        for file in files {
            guard kind.fileExtensions.contains(file.pathExtension.lowercased()) else { throw RuriError.message(Messages.CoreContentManager.importedIDsText2(String(describing: kind.fileExtensions.map { "." + $0 }.joined(separator: Messages.CoreContentManager.importedIDsText1.localized)))) }
            _ = try Archive(url: file, accessMode: .read)
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let info = kind == .mod ? Self.modInfo(file) : nil
            if let id = info?.id, existing.contains(where: { $0.modID == id }) || !importedIDs.insert(id).inserted { throw RuriError.message(Messages.CoreContentManager.idText1(String(describing: info?.name ?? id))) }
            let record = ManagedContent(provider: "local", projectID: UUID().uuidString, versionID: "local", title: info?.name ?? file.deletingPathExtension().lastPathComponent, versionName: info?.version ?? Messages.CoreContentManager.recordText2.localized, kind: kind, filename: file.lastPathComponent, size: Int64(size))
            plans.append(ContentInstallation(record: record, source: file))
        }
        try install(plans)
    }
    public func remove(_ file: LocalContentFile) throws { _ = try remove([file]) }
    struct ModInfo { let id: String?; let name: String?; let version: String? }
    static func modInfo(_ url: URL) -> ModInfo? {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) } catch { return nil }
        for path in ["fabric.mod.json", "quilt.mod.json", "litemod.json"] {
            guard let entry = archive[path], entry.uncompressedSize <= 1024 * 1024 else { continue }
            var data = Data()
            guard (try? archive.extract(entry) { data.append($0) }) != nil,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if let quilt = object["quilt_loader"] as? [String: Any] {
                let metadata = quilt["metadata"] as? [String: Any]
                return ModInfo(id: quilt["id"] as? String, name: metadata?["name"] as? String, version: quilt["version"] as? String)
            }
            if path == "litemod.json" { return ModInfo(id: object["name"] as? String, name: object["displayName"] as? String ?? object["name"] as? String, version: object["version"] as? String) }
            return ModInfo(id: object["id"] as? String, name: object["name"] as? String, version: object["version"] as? String)
        }
        return nil
    }
}
