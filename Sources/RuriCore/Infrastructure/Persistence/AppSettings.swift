import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var concurrentDownloads = 8
    public var microsoftClientID = ""
    public var showSnapshots = false
    public var defaultMemoryMB = 4096 {
        didSet { if defaultMemorySettings != nil { defaultMemorySettings?.maximumMB = defaultMemoryMB; defaultMemorySettings?.mode = .manual } }
    }
    public var defaultMemorySettings: MemorySettings?
    public var appearance = "system"
    public var downloadSource: DownloadSource?
    public var isolationPolicy: GameIsolationPolicy?
    public var defaultJava: JavaSelection?
    public var javaLocations: [JavaLocation]?
    public var defaultJVMArguments: String?
    public var defaultGameArguments: String?
    public var defaultWindow: GameWindowSize?
    public var defaultLaunchPresentation: LaunchPresentation?
    public init() {}
}
