import Foundation
import RuriLocalization

/// Which save a run was spent in. Either the launcher chose the destination
/// (quick play), or the save's own `LastPlayed` stamp is read back after the
/// game exits. Nothing is inferred from a run that left no trace in `saves/`.
public struct GameWorldPlay: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case quickPlay, detected }
    public var folder: String
    public var name: String
    public var lastPlayed: Date?
    public var source: Source
    public init(folder: String, name: String, lastPlayed: Date? = nil, source: Source) {
        self.folder = folder; self.name = name; self.lastPlayed = lastPlayed; self.source = source
    }
    package var isValid: Bool {
        !folder.isEmpty && folder.utf8.count <= 255 && name.utf8.count <= 1024 &&
        !folder.contains("/") && !folder.contains("\\") && folder != "." && folder != ".." &&
        !folder.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
