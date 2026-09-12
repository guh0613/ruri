import RuriLocalization
import Foundation

/// Reads an existing repository without creating launcher metadata or changing
/// another launcher's settings. A bad version remains visible beside valid ones.
public actor MinecraftDirectoryReader {
    public init() {}

    public func scan(_ selection: URL) throws -> MinecraftDirectoryCatalog { try scanNow(selection) }

    nonisolated func scanNow(_ selection: URL, allowEmpty: Bool = false) throws -> MinecraftDirectoryCatalog {
        let (root, selected) = try Self.repository(for: selection, allowEmpty: allowEmpty)
        let identity = try RunDirectoryCopyJournal.Identity.read(root)
        let importing = try RepositoryImportStore.reservedVersionNames(in: root).union(RepositoryMoveReservation.names(in: root))
        let versions = root.appendingPathComponent("versions")
        let children = FileManager.default.fileExists(atPath: versions.path) ? try FileTree.children(in: versions) : []
        guard children.count <= 2_000 else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.tooManyVersions) }
        var reader = MinecraftDirectoryScan(root: root)
        var result: [MinecraftDirectoryVersion] = []
        for directory in children {
            try Task.checkCancellation()
            // A repository import publishes files before registering its UUID.
            // Its journal, rather than discovery, owns the incomplete profile.
            if importing.contains(directory.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()) ||
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(RepositoryImportTransaction.markerName).path) { continue }
            let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true || info.isSymbolicLink == true else { continue }
            let id = directory.lastPathComponent
            do {
                guard info.isSymbolicLink != true else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.versionDirectorySymlink) }
                let parsed = try reader.version(id)
                let locations = try reader.locations(version: id, directory: directory)
                result.append(.init(id: id, directory: directory, gameVersion: parsed.gameVersion, components: parsed.components,
                                    gameLocations: locations.values, suggestedLocationID: locations.suggested,
                                    warnings: parsed.warnings + locations.warnings, issue: nil, documents: reader.documents))
            } catch is CancellationError { throw CancellationError() }
            catch {
                result.append(.init(id: id, directory: directory, gameVersion: nil, components: [], gameLocations: [], suggestedLocationID: nil,
                                    warnings: [], issue: error.localizedDescription, documents: []))
            }
            reader.documents = []
        }
        let currentChildren = FileManager.default.fileExists(atPath: versions.path) ? try FileTree.children(in: versions) : []
        guard identity.matches(root), currentChildren.map(\.lastPathComponent) == children.map(\.lastPathComponent),
              try RepositoryImportStore.reservedVersionNames(in: root).union(RepositoryMoveReservation.names(in: root)) == importing else {
            throw RuriError.message(Messages.CoreMinecraftDirectoryReader.versionsChangedDuringRead)
        }
        guard allowEmpty || !result.isEmpty else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.noVersionsFound) }
        return .init(id: UUID(), directory: root, selectedVersionID: selected, versions: result, identity: identity)
    }

    public func validate(_ version: MinecraftDirectoryVersion, in catalog: MinecraftDirectoryCatalog) throws { try validateNow(version, in: catalog) }

    nonisolated func validateNow(_ version: MinecraftDirectoryVersion, in catalog: MinecraftDirectoryCatalog) throws {
        guard catalog.identity.matches(catalog.directory), catalog.versions.contains(where: { $0.id == version.id && $0.directory == version.directory }), version.issue == nil else {
            throw RuriError.message(Messages.CoreMinecraftDirectoryReader.directoryUnavailableAfterPreview)
        }
        var reader = MinecraftDirectoryScan(root: catalog.directory)
        for document in version.documents {
            try Task.checkCancellation()
            let actual = reader.exists(document.url) ? try reader.read(document.url) : nil
            guard actual == document.data else {
                throw RuriError.message(Messages.CoreMinecraftDirectoryReader.settingsChangedAfterPreview)
            }
        }
        let current = try reader.version(version.id)
        guard current.gameVersion == version.gameVersion, current.components == version.components, catalog.identity.matches(catalog.directory) else {
            throw RuriError.message(Messages.CoreMinecraftDirectoryReader.componentsChangedAfterPreview)
        }
    }

    private static func repository(for selection: URL, allowEmpty: Bool) throws -> (URL, String?) {
        let url = selection.standardizedFileURL
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard info.isSymbolicLink != true else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.minecraftDirectoryRequired) }
        let directory = info.isDirectory == true ? url : url.deletingLastPathComponent()
        let root: URL, selected: String?
        if isDirectory(directory.appendingPathComponent("versions")) { root = directory; selected = nil }
        else if directory.lastPathComponent == "versions" { root = directory.deletingLastPathComponent(); selected = nil }
        else if directory.deletingLastPathComponent().lastPathComponent == "versions" {
            root = directory.deletingLastPathComponent().deletingLastPathComponent(); selected = directory.lastPathComponent
        } else if allowEmpty && info.isDirectory == true { root = directory; selected = nil
        } else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.versionsFolderMissing) }
        if info.isDirectory != true {
            guard let selected, info.isRegularFile == true, url.lastPathComponent == selected + ".json" else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.versionFolderRequired) }
        }
        guard isDirectory(root), isDirectory(root.appendingPathComponent("versions")) || (allowEmpty && !FileManager.default.fileExists(atPath: root.appendingPathComponent("versions").path)) else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.minecraftDirectoryMissing) }
        return (root.resolvingSymlinksInPath(), selected)
    }
    private static func isDirectory(_ url: URL) -> Bool {
        let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return info?.isDirectory == true && info?.isSymbolicLink != true
    }
}

struct MinecraftDirectoryScan {
    let root: URL
    var documents: [MinecraftDirectoryDocument] = []
    private var cache: [URL: Data] = [:]
    private var totalBytes = 0

    init(root: URL) { self.root = root }
    mutating func read(_ url: URL) throws -> Data {
        let data: Data
        if let existing = cache[url] { data = existing }
        else {
            guard totalBytes < 64 * 1024 * 1024 else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.manifestTooLarge) }
            data = try readFile(url, limit: min(4 * 1024 * 1024, 64 * 1024 * 1024 - totalBytes))
            totalBytes += data.count
            guard totalBytes <= 64 * 1024 * 1024 else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.manifestTooLarge) }
            cache[url] = data
        }
        if !documents.contains(where: { $0.url == url }) { documents.append(.init(url: url, data: data)) }
        return data
    }
    private func readFile(_ url: URL, limit: Int) throws -> Data {
        let prefix = root.path + "/"
        guard url.path.hasPrefix(prefix), try path(String(url.path.dropFirst(prefix.count))).path == url.path else {
            throw RuriError.message(Messages.CoreMinecraftDirectoryReader.symlinkInManifest(url.lastPathComponent))
        }
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.unableToReadManifest(url.lastPathComponent)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0, before.st_size <= limit else {
            throw RuriError.message(Messages.CoreMinecraftDirectoryReader.nonRegularManifest(url.lastPathComponent))
        }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        var after = stat(), location = stat()
        guard data.count == before.st_size, fstat(fd, &after) == 0, lstat(url.path, &location) == 0,
              [after, location].allSatisfy({ $0.st_dev == before.st_dev && $0.st_ino == before.st_ino && $0.st_size == before.st_size &&
                  $0.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec && $0.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec }) else {
            throw RuriError.message(Messages.CoreMinecraftDirectoryReader.manifestChangedDuringRead)
        }
        return data
    }
    mutating func object(_ url: URL) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: read(url)) as? [String: Any] else { throw RuriError.message(Messages.CoreMinecraftDirectoryReader.invalidManifestObject(url.lastPathComponent)) }
        return value
    }
    mutating func optionalObject(_ url: URL) throws -> [String: Any]? {
        guard exists(url) else {
            if !documents.contains(where: { $0.url == url }) { documents.append(.init(url: url, data: nil)) }
            return nil
        }
        return try object(url)
    }
    func path(_ relative: String) throws -> URL { try LauncherPaths.safePath(relative, within: root) }
    func exists(_ url: URL) -> Bool {
        var info = stat(); return lstat(url.path, &info) == 0 || errno != ENOENT
    }
}
