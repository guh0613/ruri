import RuriLocalization
import Foundation
import ZIPFoundation

public enum ContentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case mod, resourcepack, shader
    public var id: String { rawValue }
    public var title: String { switch self { case .mod: Messages.CoreContentManager.mods.localized; case .resourcepack: Messages.CoreContentManager.resourcePacks.localized; case .shader: Messages.CoreContentManager.shaders.localized } }
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
    /// Original acquisition source; online identification can add a provider without losing this.
    public var installationSource: String? = nil
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
    public var metadata: LocalModMetadata? = nil
    public internal(set) var packMetadata: LocalPackMetadata? = nil
    public internal(set) var identities: [ContentIdentity] = []
    public internal(set) var translation: ModNameIndex.Entry? = nil
    public internal(set) var metadataLoaded = true
    var stamp: LocalContentStamp? = nil
    private var chineseTitle: String? = nil
    private var searchText = ""
    init(url: URL, filename: String, title: String, version: String?, modID: String?, kind: ContentKind, enabled: Bool, size: Int64, managed: ManagedContent?, metadata: LocalModMetadata? = nil) {
        self.url = url; self.filename = filename; self.title = title; self.version = version; self.modID = modID
        self.kind = kind; self.enabled = enabled; self.size = size; self.managed = managed; self.metadata = metadata
    }
    public var isDirectory: Bool { stamp?.isDirectory == true }
    public var contentRevision: String { stamp?.key ?? id }
    public var localIconPath: String? { metadata?.iconPath ?? packMetadata?.iconPath }
    public var onlineIdentity: ContentIdentity? {
        identities.first(where: { $0.record.provider == managed?.provider }) ?? identities.first
    }
    public var summary: String? { metadata?.summary ?? packMetadata?.summary ?? onlineIdentity?.summary }
    public var presentationRevision: String { "\(stamp?.key ?? id):\(localIconPath ?? ""):\(onlineIdentity?.iconURL?.absoluteString ?? "")" }
    public var displayTitle: String {
        LocalizationContext.current.language.hasPrefix("zh") ? chineseTitle ?? title : title
    }
    public static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    public func matches(searchKey: String) -> Bool { searchKey.isEmpty || searchText.contains(searchKey) }
    public func presenting(identities matches: [ContentIdentity]) -> Self {
        presenting(metadata, pack: packMetadata, identities: matches, loaded: metadataLoaded)
    }
    public func compatibility(with game: ResourcePackFormat?) -> ResourcePackCompatibility {
        guard kind == .resourcepack, let packMetadata else { return .unknown }
        switch packMetadata.state {
        case .valid: return packMetadata.format?.compatibility(with: game) ?? .invalid
        case .missingMetadata: return .missingMetadata
        default: return .invalid
        }
    }
    func presenting(_ info: LocalModMetadata?, pack: LocalPackMetadata? = nil, identities: [ContentIdentity] = [], loaded: Bool) -> Self {
        let identities = identities.filter { $0.record.kind == kind }
        let online = identities.first(where: { $0.record.provider == managed?.provider }) ?? identities.first
        var file = Self(url: url, filename: filename,
                        title: info?.name ?? online?.record.title ?? managed?.title ?? (isDirectory ? filename : URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent),
                        version: info?.version ?? online?.record.versionName ?? (managed?.provider == "local" ? nil : managed?.versionName), modID: info?.id,
                        kind: kind, enabled: enabled, size: size, managed: managed, metadata: info)
        file.stamp = stamp; file.metadataLoaded = loaded
        file.packMetadata = pack; file.identities = identities
        if kind == .mod, loaded {
            file.translation = ModNameIndex.shared.match(id: file.modID, name: file.title)
            if let entry = file.translation, entry.hasChineseName, entry.chineseName != file.title {
                file.chineseTitle = "\(file.title) (\(entry.chineseName))"
            }
        }
        file.searchText = Self.searchKey([file.title, filename, file.modID ?? "", file.translation?.searchText ?? "", kind == .mod ? "" : file.summary ?? ""].joined(separator: "\n"))
        return file
    }
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
        guard pieces.count == 2, ContentKind.allCases.contains(where: { $0.folder == pieces[0] }) else { throw RuriError.message(Messages.CoreContentManager.invalidContentPath(path)) }
        let directory = root.appendingPathComponent(String(pieces[0]))
        let target = directory.appendingPathComponent(String(pieces[1]))
        for url in [directory, target] where (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw RuriError.message(Messages.CoreContentManager.symlinkUnmodified(url.lastPathComponent))
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
        try OperationReadPolicy.requireRecoveryPermission(paths: paths, kind: "content", instanceID: instanceID)
        let journalURL = transactionURL.appendingPathComponent("journal.json")
        if fm.fileExists(atPath: transactionURL.appendingPathComponent("committed").path) || !fm.fileExists(atPath: journalURL.path) {
            try fm.removeItem(at: transactionURL); return
        }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        for path in journal.originals {
            let backup = try LauncherPaths.safePath(path, within: transactionURL.appendingPathComponent("backups"))
            guard journal.affected.contains(path), Self.supportsContentType((try? fm.attributesOfItem(atPath: backup.path)[.type]) as? FileAttributeType, path: path) else { throw RuriError.message(Messages.CoreContentManager.missingRestoreBackup(path, transactionURL.path)) }
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
    public func install(_ incoming: [ContentInstallation], expecting expectedRecords: [ManagedContent]? = nil, enabling: Set<String> = [], allowingMissing: Set<String> = []) throws {
        try lock(); defer { unlock() }
        try recover(); try Task.checkCancellation()
        let fm = FileManager.default
        let oldRecords = try readRecords()
        if let expectedRecords {
            guard oldRecords.sorted(by: { $0.id < $1.id }) == expectedRecords.sorted(by: { $0.id < $1.id }) else { throw RuriError.message(Messages.Discovery.contentChanged) }
            for item in incoming {
                let expected = expectedRecords.first { $0.id == item.record.id }
                let actual = oldRecords.first { $0.id == item.record.id }
                let present = try actual.map { FileManager.default.fileExists(atPath: try contentURL($0.relativePath).path) } ?? true
                guard actual == expected, present || allowingMissing.contains(item.record.id) else {
                    throw RuriError.message(Messages.CoreContentManager.contentChangedAfterPreview(item.record.title))
                }
            }
        }
        var installs = incoming
        guard Set(installs.map { $0.record.id }).count == installs.count else { throw RuriError.message(Messages.CoreContentManager.duplicateProjectVersions) }
        // Preserve a user's disabled state when updating a project.
        for i in installs.indices {
            if let old = oldRecords.first(where: { $0.id == installs[i].record.id }) {
                installs[i].record.enabled = old.enabled
                installs[i].record.installationSource = old.installationSource
            }
            if enabling.contains(installs[i].record.id) { installs[i].record.enabled = true }
            let record = installs[i].record
            guard !record.filename.contains("/"), !record.filename.contains("\\"), record.kind.fileExtensions.contains(URL(fileURLWithPath: record.filename).pathExtension.lowercased()) else { throw RuriError.message(Messages.CoreContentManager.invalidContentFilename(record.filename)) }
            let check = DownloadItem(url: nil, destination: installs[i].source, sha1: record.sha1, sha512: record.sha512, md5: record.md5, size: record.size)
            guard DownloadManager.valid(installs[i].source, item: check) else { throw RuriError.message(Messages.CoreContentManager.pendingFileValidationFailed(record.filename)) }
        }
        let newPaths = installs.map { $0.record.relativePath }
        guard Set(newPaths).count == newPaths.count else { throw RuriError.message(Messages.CoreContentManager.duplicateContentFilenames) }
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
            guard unavailable.isEmpty else { throw RuriError.message(Messages.CoreContentManager.requiredDependencyDisabled(record.title)) }
        }
        let replaced = oldRecords.filter { incomingIDs.contains($0.id) }
        for old in replaced {
            let file = try contentURL(old.relativePath)
            if fm.fileExists(atPath: file.path) {
                let check = DownloadItem(url: nil, destination: file, sha1: old.sha1, sha512: old.sha512, md5: old.md5, size: old.size)
                guard DownloadManager.valid(file, item: check) else { throw RuriError.message(Messages.CoreContentManager.externallyModifiedContent(old.filename)) }
            }
        }
        let replacedPaths = Set(replaced.map(\.relativePath))
        for path in newPaths where !replacedPaths.contains(path) {
            let target = try contentURL(path)
            guard !fm.fileExists(atPath: target.path) else { throw RuriError.message(Messages.CoreContentManager.targetFileConflict(target.lastPathComponent)) }
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
    public func scan(_ kind: ContentKind, cachedOnly: Bool = false) throws -> [LocalContentFile] {
        try lock(); defer { unlock() }
        try recover()
        let managed = Dictionary(try readRecords().filter { $0.kind == kind }.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let cache = LocalContentMetadataCache.shared(in: paths.cache)
        defer { if !cachedOnly { cache.flush() } }
        let directory = root.appendingPathComponent(kind.folder)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]).compactMap { url in
            try Task.checkCancellation()
            let enabled = !url.lastPathComponent.hasSuffix(".disabled")
            let filename = enabled ? url.lastPathComponent : String(url.lastPathComponent.dropLast(9))
            guard let stamp = LocalContentStamp.read(url, allowDirectory: kind != .mod) else { return nil }
            if stamp.isDirectory {
                guard Self.isPackDirectory(url, kind: kind) else { return nil }
            } else if !kind.fileExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) { return nil }
            let record = managed["\(kind.folder)/\(url.lastPathComponent)"]
            let cached = cachedOnly ? cache.cached(stamp, kind: kind) : cache.resolve(url, stamp: stamp, kind: kind)
            var file = LocalContentFile(url: url, filename: filename, title: filename, version: nil, modID: nil, kind: kind, enabled: enabled, size: stamp.size, managed: record)
            file.stamp = stamp
            return file.presenting(cached?.metadata, pack: cached?.pack, identities: cached?.identities ?? [], loaded: cached?.isParsed == true)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    static func isPackDirectory(_ url: URL, kind: ContentKind) -> Bool {
        guard kind != .mod else { return false }
        let child = url.appendingPathComponent(kind == .resourcepack ? "pack.mcmeta" : "shaders")
        guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { return false }
        return kind == .resourcepack ? values.isRegularFile == true : values.isDirectory == true
    }
    static func supportsContentType(_ type: FileAttributeType?, path: String) -> Bool {
        type == .typeRegular || (type == .typeDirectory && ["resourcepacks", "shaderpacks"].contains(String(path.split(separator: "/").first ?? "")))
    }
    /// How many files of a kind the instance holds, without opening them, for
    /// summaries that need no titles or versions.
    public func count(_ kind: ContentKind) throws -> (total: Int, disabled: Int) {
        try lock(); defer { unlock() }
        try recover()
        let directory = root.appendingPathComponent(kind.folder)
        guard FileManager.default.fileExists(atPath: directory.path) else { return (0, 0) }
        var total = 0, disabled = 0
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            let enabled = !url.lastPathComponent.hasSuffix(".disabled")
            let filename = enabled ? url.lastPathComponent : String(url.lastPathComponent.dropLast(9))
            guard (values.isDirectory == true && Self.isPackDirectory(url, kind: kind)) ||
                    (values.isRegularFile == true && kind.fileExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())) else { continue }
            total += 1
            if !enabled { disabled += 1 }
        }
        return (total, disabled)
    }
    public func setEnabled(_ enabled: Bool, file: LocalContentFile) throws {
        try setEnabled(enabled, files: [file])
    }
    public func importFiles(_ files: [URL], kind: ContentKind) throws {
        try lock(); defer { unlock() }
        var plans: [ContentInstallation] = []
        let existing = try scan(kind)
        var importedIDs = Set<String>()
        var containsDirectory = false
        for file in files {
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let directory = values.isDirectory == true
            guard values.isSymbolicLink != true else { throw RuriError.message(Messages.CoreContentManager.symlinkUnmodified(file.lastPathComponent)) }
            if directory {
                guard Self.isPackDirectory(file, kind: kind) else { throw RuriError.message(Messages.ContentDetails.invalidPackFolder) }
                containsDirectory = true
            } else {
                guard kind.fileExtensions.contains(file.pathExtension.lowercased()) else { throw RuriError.message(Messages.CoreContentManager.chooseFiles(String(describing: kind.fileExtensions.map { "." + $0 }.joined(separator: Messages.CoreContentManager.importedIDsSeparator.localized)))) }
                _ = try Archive(url: file, accessMode: .read)
            }
            let size = directory ? 0 : values.fileSize ?? 0
            let info = kind == .mod ? Self.modInfo(file) : nil
            if let id = info?.id, existing.contains(where: { $0.modID == id }) || !importedIDs.insert(id).inserted { throw RuriError.message(Messages.CoreContentManager.duplicateModID(String(describing: info?.name ?? id))) }
            let record = ManagedContent(provider: "local", projectID: UUID().uuidString, versionID: "local", title: info?.name ?? (directory ? file.lastPathComponent : file.deletingPathExtension().lastPathComponent), versionName: info?.version ?? Messages.CoreContentManager.localFile.localized, kind: kind, filename: file.lastPathComponent, size: Int64(size))
            plans.append(ContentInstallation(record: record, source: file))
        }
        if containsDirectory { try importIncludingFolders(plans) }
        else { try install(plans) }
    }
    private func importIncludingFolders(_ plans: [ContentInstallation]) throws {
        try recover(); try Task.checkCancellation()
        let records = try readRecords(), paths = plans.map { $0.record.relativePath }
        guard Set(paths).count == paths.count else { throw RuriError.message(Messages.CoreContentManager.duplicateContentFilenames) }
        for path in paths {
            guard !FileManager.default.fileExists(atPath: try contentURL(path).path) else { throw RuriError.message(Messages.CoreContentManager.targetFileConflict(path)) }
        }
        for plan in plans {
            let source = plan.source.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            let destination = try contentURL(plan.record.relativePath).standardizedFileURL.resolvingSymlinksInPath().path + "/"
            guard !destination.hasPrefix(source) else { throw RuriError.message(Messages.CoreContentManager.targetFileConflict(plan.record.filename)) }
        }
        try changeFiles(affected: paths, oldRecords: records) {
            for plan in plans {
                let destination = try contentURL(plan.record.relativePath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: plan.source, to: destination)
            }
            try writeRecords(records.filter { !paths.contains($0.relativePath) } + plans.map(\.record))
        }
    }
    public func remove(_ file: LocalContentFile) throws { _ = try remove([file]) }
    struct ModInfo { let id: String?; let name: String?; let version: String? }
    static func modInfo(_ url: URL) -> ModInfo? {
        LocalModMetadata.read(url).map { ModInfo(id: $0.id, name: $0.name, version: $0.version) }
    }
}
