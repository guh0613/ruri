import RuriLocalization
import Foundation
import Darwin

/// A user-selected game root, separate from Ruri's managed instance metadata.
/// Its marker travels with Finder moves and detects replacement at an old path.
public struct CustomRunDirectory: Codable, Identifiable, Equatable, Sendable {
    package init(id: UUID, url: URL, bookmark: Data? = nil, createdAt: Date) {
        self.id = id
        self.url = url
        self.bookmark = bookmark
        self.createdAt = createdAt
    }

    public let id: UUID
    public var url: URL
    public var bookmark: Data?
    public let createdAt: Date
    package struct Marker: Codable {
        package let version: Int
        package let id: UUID
        package init(version: Int, id: UUID) { self.version = version; self.id = id }
    }
    package static let markerPath = ".ruri/run-directory.json"

    public func isSameLocation(as other: Self) -> Bool {
        id == other.id && url.standardizedFileURL.path == other.url.standardizedFileURL.path
    }
    package func validateConfiguration() throws {
        guard id != GameDirectory.defaultID, url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"),
              url.path.count <= 32768, (bookmark?.count ?? 0) <= 1_048_576 else { throw RuriError.message(Messages.CoreCustomRunDirectory.invalidConfiguration) }
    }
    public func validateAvailability() throws {
        do {
            try validateConfiguration()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw RuriError.message(Messages.CoreCustomRunDirectory.pathUnlinked) }
            let record = try Self.readMarker(SessionFileSystem.safePath(Self.markerPath, within: url))
            guard record.id == id else { throw RuriError.message(Messages.CoreCustomRunDirectory.directoryIdentityChanged) }
        } catch {
            throw RuriError.message(Messages.CoreCustomRunDirectory.directoryUnavailable(url.path, error.localizedDescription))
        }
    }
    public func resolvingBookmark() -> Self {
        guard let bookmark else { return self }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return self }
        var result = self; result.url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? result.validateAvailability()) != nil else { return self }
        if stale { result.bookmark = try? result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        return result
    }
    package static func readMarker(_ url: URL) throws -> Marker {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreCustomRunDirectory.markerUnreadable) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= 4096 else { throw RuriError.message(Messages.CoreCustomRunDirectory.invalidMarker) }
        let data = try handle.read(upToCount: 4097) ?? Data()
        guard data.count <= 4096 else { throw RuriError.message(Messages.CoreCustomRunDirectory.oversizedMarker) }
        let marker = try JSONDecoder().decode(Marker.self, from: data)
        guard marker.version == 1, marker.id != GameDirectory.defaultID else { throw RuriError.message(Messages.CoreCustomRunDirectory.invalidMarkerVersion) }
        return marker
    }
}
