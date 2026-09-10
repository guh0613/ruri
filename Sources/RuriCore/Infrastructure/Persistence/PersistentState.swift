import Foundation

public struct PersistentState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision: UUID?
    public var instances: [GameInstance] = []
    public var accounts: [Account] = []
    public var activeAccountID: UUID?
    public var selectedInstanceID: UUID?
    public var settings = AppSettings()
    public var gameDirectories: [GameDirectory]?
    public var detachedMinecraftFolders: [DetachedMinecraftFolder]?
    public var selectedDirectoryID: UUID?
    public init() {}
}
