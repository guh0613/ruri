import RuriLocalization
import Foundation

/// A registered game folder. Standard Minecraft repositories own their
/// resources; older Ruri collections retain the shared launcher cache.
public struct GameDirectory: Codable, Identifiable, Equatable, Sendable {
    package init(id: UUID, name: String, url: URL, bookmark: Data? = nil, createdAt: Date, layout: Layout? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.bookmark = bookmark
        self.createdAt = createdAt
        self.layout = layout
    }

    public static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public let id: UUID
    public var name: String
    public var url: URL
    public var bookmark: Data?
    public let createdAt: Date
    public enum Layout: String, Codable, Sendable { case managed, minecraft }
    public var layout: Layout?
    public var isMinecraft: Bool { layout == .minecraft }
    package static let markerName = ".ruri-directory.json"
    package struct Marker: Codable {
        package let schema: Int
        package let id: UUID
        package var layout: Layout?
        package init(schema: Int, id: UUID, layout: Layout? = nil) { self.schema = schema; self.id = id; self.layout = layout }
    }

    public func validateAvailability() throws {
        do {
            guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message(Messages.CoreGameDirectory.pathNotDirectory) }
            let marker = url.appendingPathComponent(Self.markerName)
            let values = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1024 else { throw RuriError.message(Messages.CoreGameDirectory.invalidMarker) }
            let record = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: marker))
            guard record.schema == 1, record.id == id, (record.layout ?? .managed) == (layout ?? .managed) else { throw RuriError.message(Messages.CoreGameDirectory.identityMismatch) }
        } catch {
            throw RuriError.message(Messages.CoreGameDirectory.inaccessibleDirectory(name, url.path, error.localizedDescription))
        }
    }

    /// Resolve Finder moves without UI or mounting an absent volume. Identity
    /// validation prevents a new folder at an old mount point from replacing it.
    public func resolvingBookmark() -> GameDirectory {
        guard let bookmark else { return self }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return self }
        var result = self; result.url = resolved.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? result.validateAvailability()) != nil else { return self }
        if stale { result.bookmark = try? result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        return result
    }

    public static func validName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw RuriError.message(Messages.CoreGameDirectory.invalidName) }
        return name
    }
}
