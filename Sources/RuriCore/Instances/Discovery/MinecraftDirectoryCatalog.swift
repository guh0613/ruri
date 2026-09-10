import Foundation

public struct MinecraftDirectoryCatalog: Identifiable, Sendable {
    public let id: UUID
    public let directory: URL
    public let selectedVersionID: String?
    public let versions: [MinecraftDirectoryVersion]
    let identity: RunDirectoryCopyJournal.Identity
}

public struct MinecraftDirectoryVersion: Identifiable, Sendable {
    public let id: String
    public let directory: URL
    public let gameVersion: String?
    public let components: [MinecraftDirectoryComponent]
    public let gameLocations: [MinecraftGameLocation]
    public let suggestedLocationID: String?
    public let warnings: [String]
    public let issue: String?
    public var subtitle: String {
        ([gameVersion ?? "Minecraft 版本待确认"] + components.map { $0.name + " " + $0.version }).joined(separator: " · ")
    }
    let documents: [MinecraftDirectoryDocument]
}

public struct MinecraftDirectoryComponent: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name + ":" + version }
    public let name: String
    public let version: String
}

public struct MinecraftGameLocation: Identifiable, Sendable {
    public var id: String { directory.path }
    public let directory: URL
    public let title: String
    public let explanation: String
    public let available: Bool
    public let contents: [String]
}

struct MinecraftDirectoryDocument: Sendable {
    let url: URL
    let data: Data?
}
