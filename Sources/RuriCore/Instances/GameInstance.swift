import RuriLocalization
import Foundation

public struct GameInstance: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var gameVersion: String
    public var loader: LoaderKind
    public var loaderVersion: String?
    public var createdAt: Date
    public var lastPlayed: Date?
    public var playTime: TimeInterval
    public var memoryMB: Int
    public var javaPath: String?
    public var javaMajor: Int?
    public var environmentVariables: String?
    public var launchCommands: LaunchCommands?
    public var extraJVMArguments: String
    public var extraGameArguments: String?
    public var supportedJavaMajors: [Int]?
    public var packLibraries: [Library]?
    /// The folder name under a registered Minecraft repository’s versions directory.
    public var repositoryVersionID: String?
    public var repositoryComponents: [MinecraftDirectoryComponent]?
    public var repositoryIssue: String?
    public var importedInstallation: ImportedMinecraftInstallation?
    public var width: Int
    public var height: Int
    public var fullscreen: Bool?
    public var launchPresentation: LaunchPresentation?
    public var macOSGameSettings: MacOSGameSettings?
    public var favorite: Bool
    /// A custom image; it takes precedence over `iconStyle`.
    public var iconPNG: Data?
    /// A built-in icon. When both are nil the loader's standard icon is shown.
    public var iconStyle: InstanceIconStyle?
    public var installed: Bool
    /// Missing in older states: the original Application Support directory.
    public var directoryID: UUID?
    public var runDirectory: GameRunDirectory?
    public var customRunDirectory: CustomRunDirectory?
    /// Stored with the binding in the same state transaction; proves a copy
    /// committed even if its process died before cleaning its journal.
    public var lastRunDirectoryChangeID: UUID?
    /// Publication receipt for a directly duplicated instance.
    public var lastInstanceCopyID: UUID?
    /// Stored atomically with a cross-collection move's new binding.
    public var lastInstanceMoveID: UUID?
    public var lastModpackUpdateID: UUID?
    public var launchOverrides: InstanceLaunchOverrides?
    /// Only set on a launch/export snapshot, never written over live preferences.
    public var frozenMemory: LaunchMemory?
    public init(name: String, gameVersion: String, loader: LoaderKind = .vanilla, loaderVersion: String? = nil) {
        id = UUID(); self.name = name; self.gameVersion = gameVersion; self.loader = loader
        self.loaderVersion = loaderVersion; createdAt = Date(); playTime = 0
        memoryMB = 4096; extraJVMArguments = ""; width = 1280; height = 800; favorite = false; installed = false
    }
    public func preferredJavaMajor(default minimum: Int) throws -> Int {
        if let selected = javaMajor {
            guard (6...99).contains(selected), selected >= minimum else { throw RuriError.message(Messages.CoreGameInstance.javaBelowRequiredVersion(String(describing: selected), String(describing: minimum))) }
            guard supportedJavaMajors?.isEmpty != false || supportedJavaMajors!.contains(selected) else { throw RuriError.message(Messages.CoreGameInstance.javaUnsupportedByPack(String(describing: selected))) }
            return selected
        }
        guard let supported = supportedJavaMajors, !supported.isEmpty else { return minimum }
        guard let selected = supported.filter({ $0 >= minimum }).min() else { throw RuriError.message(Messages.CoreGameInstance.packJavaVersionMismatch(String(describing: minimum))) }
        return selected
    }
    public var subtitle: String {
        if let details = repositoryComponents ?? importedInstallation?.components {
            let components = details.map { $0.name + " " + $0.version }
            return (["Minecraft \(gameVersion)"] + (components.isEmpty ? [Messages.CoreGameInstance.vanilla.localized] : components)).joined(separator: " · ")
        }
        return loader == .vanilla ? "Minecraft \(gameVersion)" : "\(gameVersion) · \(loader.title) \(loaderVersion ?? "")"
    }
}
