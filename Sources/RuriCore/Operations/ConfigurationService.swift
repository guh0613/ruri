import RuriLocalization
import Foundation

public struct ConfigurationField: Codable, Sendable {
    public let name: String
    public let type: String
    public var nullable = false
    public var values: [String] = []
    public var minimum: Int? = nil
    public var maximum: Int? = nil
    public var sensitive = false
}

public struct ConfigurationPatch: Decodable, Sendable {
    public var set: [String: OperationValue] = [:]
    public var reset: [String] = []
    public var inherit: [String] = []
    public init(set: [String: OperationValue] = [:], reset: [String] = [], inherit: [String] = []) { self.set = set; self.reset = reset; self.inherit = inherit }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer().decode([String: OperationValue].self)
        guard Set(c.keys).isSubset(of: ["set", "reset", "inherit"]) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t8568ceb9ae27.localized) }
        set = try c["set"]?.decode([String: OperationValue].self) ?? [:]
        reset = try c["reset"]?.decode([String].self) ?? []
        inherit = try c["inherit"]?.decode([String].self) ?? []
    }
}

public struct ConfigurationService: Sendable {
    public let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public static let appFields: [ConfigurationField] = [
        .init(name: "appearance", type: "string", values: ["system", "light", "dark"]),
        .init(name: "concurrentDownloads", type: "integer", minimum: 1, maximum: 16),
        .init(name: "downloadSource", type: "string", values: ["automatic", "official", "bmclapi"]),
        .init(name: "isolationPolicy", type: "string", values: ["always", "modded", "never"]),
        .init(name: "showSnapshots", type: "boolean"), .init(name: "microsoftClientID", type: "string")
    ]
    public static let launchFields: [ConfigurationField] = [
        .init(name: "memory.mode", type: "string", values: ["automatic", "manual"]),
        .init(name: "memory.maximumMB", type: "integer", minimum: 512, maximum: 131072),
        .init(name: "memory.initialMB", type: "integer", nullable: true, minimum: 16, maximum: 131072),
        .init(name: "memory.metaspaceMB", type: "integer", nullable: true, minimum: 16, maximum: 131072),
        .init(name: "java.mode", type: "string", values: ["automatic", "major", "path"]),
        .init(name: "java.major", type: "integer", nullable: true, minimum: 6, maximum: 99),
        .init(name: "java.path", type: "string", nullable: true),
        .init(name: "jvmArguments", type: "string"), .init(name: "gameArguments", type: "string"),
        .init(name: "window.width", type: "integer", minimum: 320, maximum: 16384),
        .init(name: "window.height", type: "integer", minimum: 240, maximum: 16384), .init(name: "window.fullscreen", type: "boolean"),
        .init(name: "presentation.hideLauncher", type: "boolean"), .init(name: "presentation.showLogs", type: "boolean"), .init(name: "presentation.debugLogging", type: "boolean"),
        .init(name: "environment", type: "string", sensitive: true),
        .init(name: "commands.enabled", type: "boolean"), .init(name: "commands.before", type: "string"), .init(name: "commands.after", type: "string"),
        .init(name: "commands.wrapper", type: "string"), .init(name: "commands.timeoutSeconds", type: "integer", minimum: 1, maximum: 3600),
        .init(name: "macOS.enabled", type: "boolean"), .init(name: "macOS.instanceAppearance", type: "boolean"), .init(name: "macOS.nativeFullscreen", type: "boolean")
    ]
    public static var groups: [String] { LaunchSettingKey.allCases.map(\.rawValue) }
    public static func schema() throws -> OperationValue {
        .object(["scopes": .array(["app", "defaults", "instance:<uuid>"].map(OperationValue.string)),
                 "app": try .encode(appFields), "launch": try .encode(launchFields), "inheritanceGroups": .array(groups.map(OperationValue.string)),
                 "patch": .object(["set": .string(Messages.CLIInterface.tba308ed7fb67.localized), "reset": .string(Messages.CLIInterface.tba6d0ed49ef6.localized), "inherit": .string(Messages.CLIInterface.t54e4e046502f.localized)])])
    }
    private func instanceID(_ scope: String) throws -> UUID? {
        if scope == "app" || scope == "defaults" { return nil }
        guard scope.hasPrefix("instance:"), let id = UUID(uuidString: String(scope.dropFirst(9))) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.te2e236614526.localized) }
        return id
    }
    private func instance(_ id: UUID, state: PersistentState) throws -> GameInstance {
        guard let value = state.instances.first(where: { $0.id == id }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t491b2168687b.localized) }; return value
    }
    public func read(scope: String, showSecrets: Bool = false) throws -> OperationValue { try report(scope: scope, state: StateStore.load(paths), showSecrets: showSecrets) }
    private func report(scope: String, state: PersistentState, showSecrets: Bool) throws -> OperationValue {
        let id = try instanceID(scope)
        var effective: OperationValue, explicit: OperationValue, sources: [String: OperationValue] = [:]
        if scope == "app" {
            effective = Self.appValues(state.settings); explicit = effective
            for field in Self.appFields { sources[field.name] = .string("app") }
        } else {
            let overrides = try id.map { try instance($0, state: state).effectiveLaunchOverrides }
            effective = Self.launchValues(overrides?.resolve(defaults: state.settings.defaultLaunchSettings) ?? state.settings.defaultLaunchSettings)
            var values: [String: OperationValue] = [:]
            for key in LaunchSettingKey.allCases {
                let inherited = overrides?.inherits(key) ?? false
                if !inherited { values[key.rawValue] = effective[key.rawValue] }
                sources[key.rawValue] = .string(inherited || id == nil ? "defaults" : "instance")
            }
            explicit = .object(values)
        }
        if !showSecrets { effective = Self.redact(effective); explicit = Self.redact(explicit) }
        return .object(["scope": .string(scope), "revision": .text(state.revision?.uuidString), "explicit": explicit, "effective": effective, "sources": .object(sources)])
    }
    public func apply(_ patch: ConfigurationPatch, scope: String, expectedRevision: UUID? = nil, dryRun: Bool = false, showSecrets: Bool = false) throws -> OperationValue {
        let id = try instanceID(scope)
        let fields = scope == "app" ? Self.appFields : Self.launchFields
        var flattened: [String: OperationValue] = [:]
        func expand(_ key: String, _ value: OperationValue) throws {
            if let object = value.object, !fields.contains(where: { $0.name == key }) {
                guard !object.isEmpty, fields.contains(where: { $0.name.hasPrefix(key + ".") }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t41f1a159c375(String(describing: key)).localized) }
                for (child, value) in object { try expand(key + "." + child, value) }
            } else {
                guard flattened[key] == nil, let field = fields.first(where: { $0.name == key }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t0e5f6b9ca429(String(describing: key)).localized) }
                try Self.validate(value, field: field); flattened[key] = value
            }
        }
        for (key, value) in patch.set { try expand(key, value) }
        guard patch.inherit.isEmpty || id != nil, patch.inherit.allSatisfy({ Self.groups.contains($0) }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t0199982aa94e.localized) }
        let operations = Array(flattened.keys) + patch.reset + patch.inherit
        for (index, key) in operations.enumerated() {
            guard fields.contains(where: { $0.name == key || $0.name.hasPrefix(key + ".") }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tca2c20d623be(String(describing: key)).localized) }
            guard !operations.dropFirst(index + 1).contains(where: { $0 == key || $0.hasPrefix(key + ".") || key.hasPrefix($0 + ".") }) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.ta78e60d41732(String(describing: key)).localized) }
        }
        var before = try StateStore.load(paths), after = before
        func mutate(_ state: inout PersistentState) throws {
            before = state
            if let expectedRevision, state.revision != expectedRevision { throw OperationFailure("STATE_CONFLICT", Messages.CLIInterface.te8a7227e2180.localized, retryable: true) }
            let baseline: OperationValue
            var overrides: InstanceLaunchOverrides?
            if scope == "app" { baseline = Self.appValues(state.settings) }
            else if let id { overrides = try instance(id, state: state).effectiveLaunchOverrides; baseline = Self.launchValues(overrides!.resolve(defaults: state.settings.defaultLaunchSettings)) }
            else { baseline = Self.launchValues(state.settings.defaultLaunchSettings) }
            var values = baseline
            let builtins = scope == "app" ? Self.appValues(AppSettings()) : Self.launchValues(LaunchSettingsValues())
            for (key, value) in flattened { Self.assign(&values, path: key.split(separator: ".").map(String.init), value: value) }
            for key in patch.reset { Self.assign(&values, path: key.split(separator: ".").map(String.init), value: Self.get(builtins, key)) }
            if scope == "app" { try Self.applyApp(values, to: &state.settings) }
            else {
                let resolved = try Self.decodeLaunch(values)
                do { try resolved.validate() }
                catch { throw OperationFailure("INVALID_ARGUMENT", error.localizedDescription) }
                if let id, let index = state.instances.firstIndex(where: { $0.id == id }) {
                    var next = overrides!
                    let fixed = InstanceLaunchOverrides(fixing: resolved)
                    for group in Set((Array(flattened.keys) + patch.reset).map { String($0.split(separator: ".")[0]) }) {
                        Self.copyGroup(group, from: fixed, into: &next)
                    }
                    for group in patch.inherit { next.setInheritance(true, for: LaunchSettingKey(rawValue: group)!, defaults: state.settings.defaultLaunchSettings) }
                    do { try next.resolve(defaults: state.settings.defaultLaunchSettings).validate() }
                    catch { throw OperationFailure("INVALID_ARGUMENT", error.localizedDescription) }
                    if next != state.instances[index].effectiveLaunchOverrides { state.instances[index].launchOverrides = next }
                } else if resolved != state.settings.defaultLaunchSettings { state.settings.defaultLaunchSettings = resolved }
            }
        }
        if dryRun { try mutate(&after) }
        else {
            // Validate before creating the state root or lock for an invalid patch.
            try mutate(&after)
            if after != before { after = try StateStore.updateIfChanged(paths, expectedRevision: expectedRevision, mutate) }
        }
        return .object(["changed": .bool(after != before), "dryRun": .bool(dryRun), "before": try report(scope: scope, state: before, showSecrets: showSecrets),
                        "after": try report(scope: scope, state: after, showSecrets: showSecrets)])
    }
    public static func get(_ value: OperationValue, _ path: String) -> OperationValue { path.split(separator: ".").reduce(value) { $0[String($1)] } }
    static func assign(_ root: inout OperationValue, path: [String], value: OperationValue) {
        guard let key = path.first else { root = value; return }
        var object = root.object ?? [:], child = object[key] ?? .null
        assign(&child, path: Array(path.dropFirst()), value: value); object[key] = child; root = .object(object)
    }
    private static func validate(_ value: OperationValue, field: ConfigurationField) throws {
        if value == .null && field.nullable { return }
        let valid: Bool
        switch field.type { case "boolean": valid = value.bool != nil; case "integer": valid = value.int != nil; default: valid = value.string != nil }
        guard valid, field.values.isEmpty || field.values.contains(value.string ?? ""),
              field.minimum == nil || (value.int ?? Int.min) >= field.minimum!, field.maximum == nil || (value.int ?? Int.max) <= field.maximum! else {
            throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t62fca6b0b13b(String(describing: field.name)).localized, details: try .encode(field))
        }
    }
    private static func appValues(_ v: AppSettings) -> OperationValue {
        .object(["appearance": .string(v.appearance), "concurrentDownloads": .integer(v.concurrentDownloads), "showSnapshots": .bool(v.showSnapshots),
                 "microsoftClientID": .string(v.microsoftClientID), "downloadSource": .string((v.downloadSource ?? .automatic).rawValue), "isolationPolicy": .string((v.isolationPolicy ?? .always).rawValue)])
    }
    private static func applyApp(_ v: OperationValue, to settings: inout AppSettings) throws {
        for field in appFields { try validate(v[field.name], field: field) }
        let client = v["microsoftClientID"].string!.trimmingCharacters(in: .whitespacesAndNewlines)
        guard client.isEmpty || UUID(uuidString: client) != nil else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t1f94c2f53310.localized) }
        settings.appearance = v["appearance"].string!; settings.concurrentDownloads = v["concurrentDownloads"].int!; settings.showSnapshots = v["showSnapshots"].bool!
        settings.microsoftClientID = client
        let source = DownloadSource(rawValue: v["downloadSource"].string!)!, policy = GameIsolationPolicy(rawValue: v["isolationPolicy"].string!)!
        if source != (settings.downloadSource ?? .automatic) { settings.downloadSource = source }
        if policy != (settings.isolationPolicy ?? .always) { settings.isolationPolicy = policy }
    }
    public static func launchValues(_ v: LaunchSettingsValues) -> OperationValue {
        let java: OperationValue
        switch v.java {
        case .automatic: java = .object(["mode": .string("automatic"), "major": .null, "path": .null])
        case .major(let n): java = .object(["mode": .string("major"), "major": .integer(n), "path": .null])
        case .path(let p): java = .object(["mode": .string("path"), "major": .null, "path": .string(p)])
        }
        return .object([
            "memory": .object(["mode": .string(v.memory.mode.rawValue), "maximumMB": .integer(v.memory.maximumMB), "initialMB": v.memory.initialMB.map(OperationValue.integer) ?? .null, "metaspaceMB": v.memory.metaspaceMB.map(OperationValue.integer) ?? .null]),
            "java": java, "jvmArguments": .string(v.jvmArguments), "gameArguments": .string(v.gameArguments), "environment": .string(v.environment),
            "window": .object(["width": .integer(v.window.width), "height": .integer(v.window.height), "fullscreen": .bool(v.window.fullscreen)]),
            "presentation": .object(["hideLauncher": .bool(v.presentation.hideLauncher), "showLogs": .bool(v.presentation.showLogs), "debugLogging": .bool(v.presentation.debugLogging)]),
            "commands": .object(["enabled": .bool(v.commands.enabled), "before": .string(v.commands.before), "after": .string(v.commands.after), "wrapper": .string(v.commands.wrapper), "timeoutSeconds": .integer(v.commands.timeoutSeconds)]),
            "macOS": .object(["enabled": .bool(v.macOS.enabled), "instanceAppearance": .bool(v.macOS.instanceAppearance), "nativeFullscreen": .bool(v.macOS.nativeFullscreen)])])
    }
    static func decodeLaunch(_ v: OperationValue) throws -> LaunchSettingsValues {
        for field in launchFields { try validate(get(v, field.name), field: field) }
        var result = LaunchSettingsValues()
        result.memory = .init(mode: MemorySettings.Mode(rawValue: v["memory"]["mode"].string!)!, maximumMB: v["memory"]["maximumMB"].int!, initialMB: v["memory"]["initialMB"].int, metaspaceMB: v["memory"]["metaspaceMB"].int)
        switch v["java"]["mode"].string {
        case "automatic": result.java = .automatic
        case "major":
            guard let major = v["java"]["major"].int else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t9b199fcf9a1f.localized) }; result.java = .major(major)
        default:
            guard let path = v["java"]["path"].string else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t15b3dd14487d.localized) }; result.java = .path(path)
        }
        result.jvmArguments = v["jvmArguments"].string!; result.gameArguments = v["gameArguments"].string!; result.environment = v["environment"].string!
        result.window = try v["window"].decode(GameWindowSize.self); result.presentation = try v["presentation"].decode(LaunchPresentation.self)
        result.commands = try v["commands"].decode(LaunchCommands.self); result.macOS = try v["macOS"].decode(MacOSGameSettings.self)
        return result
    }
    static func copyGroup(_ group: String, from v: InstanceLaunchOverrides, into target: inout InstanceLaunchOverrides) {
        switch LaunchSettingKey(rawValue: group)! {
        case .memory: target.memory = v.memory; case .java: target.java = v.java; case .window: target.window = v.window
        case .jvmArguments: target.jvmArguments = v.jvmArguments; case .gameArguments: target.gameArguments = v.gameArguments
        case .presentation: target.presentation = v.presentation; case .environment: target.environment = v.environment
        case .commands: target.commands = v.commands; case .macOS: target.macOS = v.macOS
        }
    }
    private static func redact(_ input: OperationValue) -> OperationValue {
        var object = input.object ?? [:]
        if let environment = object["environment"]?.string {
            object["environment"] = .object(["redacted": .bool(true), "names": .array(((try? LaunchEnvironment(environment).entries.map(\.name)) ?? []).map(OperationValue.string))])
        }
        return .object(object)
    }
}
