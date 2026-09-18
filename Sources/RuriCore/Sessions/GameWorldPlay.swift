import Foundation

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
    var isValid: Bool {
        !folder.isEmpty && folder.utf8.count <= 255 && name.utf8.count <= 1024 &&
        !folder.contains("/") && !folder.contains("\\") && folder != "." && folder != ".." &&
        !folder.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

extension GameSession {
    /// Fold a read-back save into a finished record. A quick-play choice keeps
    /// its provenance when the save agrees, and is replaced when the player
    /// moved on to another one during the same run.
    mutating func applyWorldPlayed(start: Date, end: Date) {
        guard let directory = gameDirectory,
              let played = GameWorldActivity.played(in: directory, start: start, end: end) else { return }
        if world?.folder == played.folder {
            world?.name = played.name; world?.lastPlayed = played.lastPlayed
        } else {
            world = played
        }
    }
}

/// Reads back which save a finished run touched. This is metadata for the
/// history page, never a launch or liveness authority: every failure simply
/// leaves the run without a save, and nothing here writes to the game folder.
enum GameWorldActivity {
    /// A save that was still being written as the process ended can stamp
    /// itself slightly after the observed exit; a clock skewed the other way
    /// must not make the previous run's save look like this one's.
    static let leadIn: TimeInterval = 60
    static let leadOut: TimeInterval = 300
    static let scanLimit = 512
    static let levelDataLimit = 8 * 1024 * 1024

    static func played(in gameDirectory: URL, start: Date, end: Date) -> GameWorldPlay? {
        guard start <= end else { return nil }
        let window = start.addingTimeInterval(-leadIn)...max(end, start).addingTimeInterval(leadOut)
        var best: GameWorldPlay?
        for world in saves(in: gameDirectory) {
            guard let played = level(of: world), let stamp = played.lastPlayed, window.contains(stamp) else { continue }
            if let current = best, let existing = current.lastPlayed, existing >= stamp { continue }
            best = played
        }
        return best
    }

    private static func saves(in gameDirectory: URL) -> [URL] {
        guard let saves = try? LauncherPaths.safePath("saves", within: gameDirectory),
              (try? saves.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true,
              let entries = try? FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        else { return [] }
        return entries.prefix(scanLimit).filter { entry in
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }

    private static func level(of world: URL) -> GameWorldPlay? {
        let folder = world.lastPathComponent
        var candidate = GameWorldPlay(folder: folder, name: folder, source: .detected)
        guard candidate.isValid else { return nil }
        guard let file = ["level.dat", "level.dat_old"].lazy.compactMap({ name -> URL? in
            let url = world.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true, (values?.fileSize ?? Int.max) <= levelDataLimit else { return nil }
            return url
        }).first, let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { return nil }
        guard var reader = try? NBTReader(data: data), let level = (try? reader.read())?["Data"] else { return nil }
        if let name = level["LevelName"]?.string, !name.isEmpty, name.utf8.count <= 1024 { candidate.name = name }
        // Minecraft stores LastPlayed as milliseconds since the epoch.
        candidate.lastPlayed = level["LastPlayed"]?.integer.flatMap { (0..<253_402_300_800_000).contains($0) ? Date(timeIntervalSince1970: Double($0) / 1000) : nil }
        return candidate
    }
}
