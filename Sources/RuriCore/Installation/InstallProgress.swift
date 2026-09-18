import Foundation
import RuriLocalization

public struct InstallProgress: Sendable {
    /// Work running alongside the main stage reports on its own track.
    public enum Track: String, Codable, Sendable { case main, gameAssets }
    public var message: LocalizedMessage
    public var stage: String { message.localized }
    public var completed: Int
    public var total: Int
    public var track: Track
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public init(_ stage: String, completed: Int = 0, total: Int = 0, track: Track = .main) {
        self.message = .verbatim(stage); self.completed = completed; self.total = total; self.track = track
    }
    public init(_ message: LocalizedMessage, completed: Int = 0, total: Int = 0, track: Track = .main) {
        self.message = message; self.completed = completed; self.total = total; self.track = track
    }
    /// Ends a parallel track, either because its work is done or because the
    /// main stage has taken it over.
    public static func finished(_ track: Track) -> InstallProgress { InstallProgress(.verbatim(""), completed: 1, total: 1, track: track) }
}
