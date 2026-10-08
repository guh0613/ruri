import Foundation

public struct MacOSGameSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var instanceAppearance = true
    public var nativeFullscreen = true
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, instanceAppearance, nativeFullscreen }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        instanceAppearance = try values.decodeIfPresent(Bool.self, forKey: .instanceAppearance) ?? true
        nativeFullscreen = try values.decodeIfPresent(Bool.self, forKey: .nativeFullscreen) ?? true
    }
}

public struct GameHostPlan: Codable, Sendable {
    package init(
        instanceID: UUID, name: String, iconPNG: Data? = nil, javaVersion: String, architecture: String, settings: MacOSGameSettings,
        fullscreen: Bool
    ) {
        self.instanceID = instanceID
        self.name = name
        self.iconPNG = iconPNG
        self.javaVersion = javaVersion
        self.architecture = architecture
        self.settings = settings
        self.fullscreen = fullscreen
    }

    public let instanceID: UUID
    public let name: String
    public let iconPNG: Data?
    public let javaVersion: String
    public let architecture: String
    public let settings: MacOSGameSettings
    public let fullscreen: Bool
}

public struct GameHostStatus: Codable, Equatable, Sendable {
    package init(
        backend: Backend, fallback: String? = nil, jvmStarted: Bool = false, windowReadyAt: Date? = nil, fullscreen: Bool = false,
        failure: String? = nil
    ) {
        self.backend = backend
        self.fallback = fallback
        self.jvmStarted = jvmStarted
        self.windowReadyAt = windowReadyAt
        self.fullscreen = fullscreen
        self.failure = failure
    }

    public enum Backend: String, Codable, Sendable { case native, java }
    public var backend: Backend
    public var fallback: String?
    public var jvmStarted = false
    public var windowReadyAt: Date?
    public var fullscreen = false
    public var failure: String?
}
