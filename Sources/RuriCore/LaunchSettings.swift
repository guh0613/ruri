import Foundation

public enum JavaSelection: Codable, Equatable, Sendable {
    case automatic
    case path(String)
    public var path: String? { if case .path(let value) = self { value } else { nil } }
}

public struct GameWindowSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int = 1280, height: Int = 800) { self.width = width; self.height = height }
}

public enum LaunchSettingKey: String, CaseIterable, Identifiable, Sendable {
    case memory, java, jvmArguments, gameArguments, window
    public var id: String { rawValue }
    public var title: String {
        switch self { case .memory: "最大内存"; case .java: "Java 运行时"; case .jvmArguments: "附加 JVM 参数"; case .gameArguments: "附加游戏参数"; case .window: "游戏窗口" }
    }
}

/// Fully resolved values used by previews, launch snapshots and portable exports.
public struct LaunchSettingsValues: Codable, Equatable, Sendable {
    public var memoryMB: Int = 4096
    public var java: JavaSelection = .automatic
    public var jvmArguments: String = ""
    public var gameArguments: String = ""
    public var window = GameWindowSize()
    public init() {}
    public func validate() throws {
        guard (512...131_072).contains(memoryMB) else { throw RuriError.message("最大内存应为 512–131072 MB。") }
        guard (320...16_384).contains(window.width), (240...16_384).contains(window.height) else { throw RuriError.message("窗口宽度应为 320–16384，高度应为 240–16384。") }
        guard jvmArguments.count <= 32768, gameArguments.count <= 32768 else { throw RuriError.message("附加启动参数过长。") }
        if let path = java.path {
            guard path.hasPrefix("/"), !path.contains("\0"), path.count <= 32768 else { throw RuriError.message("请选择 Java 可执行文件的完整路径。") }
        }
        _ = try ArgumentTokenizer.split(jvmArguments)
        _ = try ArgumentTokenizer.split(gameArguments)
    }
}

/// Nil means inheritance; explicit automatic Java and empty arguments are real
/// overrides. Each value and its inheritance choice share one state field.
public struct InstanceLaunchOverrides: Codable, Equatable, Sendable {
    public var memoryMB: Int?
    public var java: JavaSelection?
    public var jvmArguments: String?
    public var gameArguments: String?
    public var window: GameWindowSize?
    public init() {}
    public init(fixing values: LaunchSettingsValues) {
        memoryMB = values.memoryMB; java = values.java; jvmArguments = values.jvmArguments
        gameArguments = values.gameArguments; window = values.window
    }
    public func resolve(defaults: LaunchSettingsValues) -> LaunchSettingsValues {
        var result = defaults
        if let memoryMB { result.memoryMB = memoryMB }; if let java { result.java = java }
        if let jvmArguments { result.jvmArguments = jvmArguments }; if let gameArguments { result.gameArguments = gameArguments }
        if let window { result.window = window }
        return result
    }
    public func inherits(_ key: LaunchSettingKey) -> Bool {
        switch key { case .memory: memoryMB == nil; case .java: java == nil; case .jvmArguments: jvmArguments == nil; case .gameArguments: gameArguments == nil; case .window: window == nil }
    }
    /// Turning inheritance off starts with the currently effective value.
    public mutating func setInheritance(_ inherit: Bool, for key: LaunchSettingKey, defaults: LaunchSettingsValues) {
        let effective = resolve(defaults: defaults)
        switch key {
        case .memory: memoryMB = inherit ? nil : effective.memoryMB
        case .java: java = inherit ? nil : effective.java
        case .jvmArguments: jvmArguments = inherit ? nil : effective.jvmArguments
        case .gameArguments: gameArguments = inherit ? nil : effective.gameArguments
        case .window: window = inherit ? nil : effective.window
        }
    }
}

extension AppSettings {
    public var defaultLaunchSettings: LaunchSettingsValues {
        get {
            var result = LaunchSettingsValues(); result.memoryMB = defaultMemoryMB
            result.java = defaultJava ?? .automatic; result.jvmArguments = defaultJVMArguments ?? ""
            result.gameArguments = defaultGameArguments ?? ""; result.window = defaultWindow ?? .init()
            return result
        }
        set {
            defaultMemoryMB = newValue.memoryMB; defaultJava = newValue.java; defaultJVMArguments = newValue.jvmArguments
            defaultGameArguments = newValue.gameArguments; defaultWindow = newValue.window
        }
    }
}

extension GameInstance {
    /// Missing override metadata is an old or imported instance. Keep every
    /// existing value fixed, including an empty argument or automatic Java.
    public var effectiveLaunchOverrides: InstanceLaunchOverrides {
        if let launchOverrides { return launchOverrides }
        var legacy = LaunchSettingsValues(); legacy.memoryMB = memoryMB; legacy.java = javaPath.map(JavaSelection.path) ?? .automatic
        legacy.jvmArguments = extraJVMArguments; legacy.gameArguments = extraGameArguments ?? ""
        legacy.window = .init(width: width, height: height)
        return .init(fixing: legacy)
    }
    public func resolvedLaunchSettings(defaults: AppSettings) -> LaunchSettingsValues {
        effectiveLaunchOverrides.resolve(defaults: defaults.defaultLaunchSettings)
    }
    /// A frozen copy for one launch/export. Never persist this over the instance
    /// being edited or installed: it deliberately removes the inheritance link.
    public func launchSnapshot(defaults: AppSettings) throws -> GameInstance {
        let settings = resolvedLaunchSettings(defaults: defaults); try settings.validate()
        var copy = self; copy.memoryMB = settings.memoryMB; copy.javaPath = settings.java.path
        copy.extraJVMArguments = settings.jvmArguments; copy.extraGameArguments = settings.gameArguments.isEmpty ? nil : settings.gameArguments
        copy.width = settings.window.width; copy.height = settings.window.height; copy.launchOverrides = nil
        return copy
    }
    func resolvingPersistedLaunchSettings(paths: LauncherPaths) throws -> GameInstance {
        guard launchOverrides != nil else { return self }
        return try launchSnapshot(defaults: StateStore.load(paths).settings)
    }
}
