import Darwin
import Foundation
import RuriLocalization

extension CustomRunDirectory {
    /// Reads a candidate identity without creating markers, bookmarks or locks.
    /// An unregistered candidate must still be registered before execution.
    public static func inspect(at selected: URL, paths: LauncherPaths) throws -> Self {
        let url = selected.standardizedFileURL.resolvingSymlinksInPath()
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message(Messages.CoreCustomRunDirectory.existingGameFolderRequired) }
        let marker = try LauncherPaths.safePath(markerPath, within: url)
        let id = FileManager.default.fileExists(atPath: marker.path) ? try readMarker(marker).id : UUID()
        let candidate = Self(id: id, url: url, bookmark: nil, createdAt: Date())
        try paths.checkCustomRunDirectory(candidate, readingIdentity: true)
        return candidate
    }

    /// Registers coordination metadata only. Existing game files are preserved.
    public static func register(at selected: URL, paths: LauncherPaths) throws -> Self {
        let url = selected.standardizedFileURL.resolvingSymlinksInPath()
        var candidate = Self(id: UUID(), url: url, bookmark: nil, createdAt: Date())
        try paths.checkCustomRunDirectory(candidate, readingIdentity: true)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message(Messages.CoreCustomRunDirectory.existingGameFolderRequired) }
        let marker = try LauncherPaths.safePath(markerPath, within: url)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lock = GameDataOperationLock(); try lock.acquire(directory: marker.deletingLastPathComponent(), name: ".location-registration.lock")
        defer { withExtendedLifetime(lock) {} }
        if FileManager.default.fileExists(atPath: marker.path) {
            let previous = try readMarker(marker)
            candidate = Self(id: previous.id, url: url, bookmark: nil, createdAt: Date())
        } else {
            try JSONEncoder().encode(Marker(version: 1, id: candidate.id)).write(to: marker, options: .withoutOverwriting)
        }
        try paths.checkCustomRunDirectory(candidate)
        candidate.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try candidate.validateAvailability()
        return candidate
    }

    public func relocated(to selected: URL, paths: LauncherPaths) throws -> Self {
        var result = self; result.url = selected.standardizedFileURL.resolvingSymlinksInPath()
        try result.validateAvailability()
        try paths.checkCustomRunDirectory(result, relocatingID: id)
        result.bookmark = try result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return result
    }
}

extension PersistentState {
    /// All references to one game root must resolve together. Otherwise a
    /// missing bookmark on one instance could split a shared location after a
    /// Finder move and make the whole directory configuration inconsistent.
    public func resolvingCustomRunDirectoryBookmarks() -> Self {
        let locations = instances.sorted { ($0.runDirectory == .custom ? 0 : 1) < ($1.runDirectory == .custom ? 0 : 1) }.compactMap(\.customRunDirectory)
        var resolved: [UUID: CustomRunDirectory] = [:]
        var ambiguous = Set<UUID>()
        for location in locations {
            if (try? location.validateAvailability()) != nil {
                if let existing = resolved[location.id], !existing.isSameLocation(as: location) { ambiguous.insert(location.id) }
                else { resolved[location.id] = location }
            }
        }
        for location in locations where resolved[location.id] == nil {
            let candidate = location.resolvingBookmark()
            if (try? candidate.validateAvailability()) != nil { resolved[location.id] = candidate }
        }
        var state = self
        state.instances = instances.map { item in
            var item = item
            if let id = item.customRunDirectory?.id, !ambiguous.contains(id), let location = resolved[id] { item.customRunDirectory = location }
            return item
        }
        return state
    }
}
