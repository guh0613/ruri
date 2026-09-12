import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageLaunchSettings(_ args: [String], paths: LauncherPaths) throws {
        let usage = Messages.CLILaunchSettingsCommands.launchSettingsUsage.localized
        guard let scope = args.first, scope == "defaults" || UUID(uuidString: scope) != nil else { throw RuriError.message(usage) }
        let id = UUID(uuidString: scope)
        if args.count > 1 {
            guard (args.count == 4 && args[1] == "set") || (args.count == 3 && args[1] == "inherit" && id != nil) else { throw RuriError.message(usage) }
            var key = args[1] == "set" && args[2] == "fullscreen" ? LaunchSettingKey.window : args[1] == "set" && args[2] == "environment-file" ? .environment : LaunchSettingKey(rawValue: args[2])
            if args[1] == "set", ["preLaunchCommand", "postExitCommand", "commandWrapper", "commandTimeout"].contains(args[2]) { key = .commands }
            let memoryDetail = args[1] == "set" && ["initialMemory", "metaspace"].contains(args[2])
            guard key != nil || memoryDetail || (args[1] == "inherit" && args[2] == "all") else { throw RuriError.message(usage) }
            try StateStore.update(paths) { state in
                let index = id.flatMap { id in state.instances.firstIndex { $0.id == id } }
                if id != nil && index == nil { throw RuriError.message(Messages.CLILaunchSettingsCommands.instanceMissing) }
                let defaults = state.settings.defaultLaunchSettings
                var overrides = index.map { state.instances[$0].effectiveLaunchOverrides } ?? .init(fixing: defaults)
                if args[1] == "inherit" {
                    if let key { overrides.setInheritance(true, for: key, defaults: defaults) } else { overrides = .init() }
                } else {
                    let value = args[3]
                    switch key ?? .memory {
                    case .memory:
                        var memory = overrides.resolve(defaults: defaults).memory
                        if args[2] == "initialMemory" {
                            guard value == "default" || Int(value) != nil else { throw RuriError.message(usage) }; memory.initialMB = Int(value)
                        } else if args[2] == "metaspace" {
                            guard value == "unlimited" || Int(value) != nil else { throw RuriError.message(usage) }; memory.metaspaceMB = Int(value)
                        } else if value == "auto" { memory.mode = .automatic }
                        else { guard let amount = Int(value) else { throw RuriError.message(usage) }; memory.mode = .manual; memory.maximumMB = amount }
                        overrides.memory = memory
                    case .java: overrides.java = value == "auto" ? .automatic : Int(value).map(JavaSelection.major) ?? .path(value)
                    case .jvmArguments: overrides.jvmArguments = value
                    case .gameArguments: overrides.gameArguments = value
                    case .window:
                        var window = overrides.resolve(defaults: defaults).window
                        if args[2] == "fullscreen" {
                            guard let flag = Bool(value) else { throw RuriError.message(usage) }; window.fullscreen = flag
                        } else {
                            let parts = value.lowercased().split(separator: "x")
                            guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { throw RuriError.message(usage) }
                            window.width = width; window.height = height
                        }
                        overrides.window = window
                    case .presentation:
                        guard ["keep", "hide", "logs"].contains(value) else { throw RuriError.message(usage) }
                        overrides.presentation = .init(hideLauncher: value == "hide", showLogs: value == "logs")
                    case .commands:
                        var commands = overrides.resolve(defaults: defaults).commands
                        switch args[2] {
                        case "preLaunchCommand": commands.before = value
                        case "postExitCommand": commands.after = value
                        case "commandWrapper": commands.wrapper = value
                        case "commandTimeout":
                            guard let seconds = Int(value) else { throw RuriError.message(usage) }; commands.timeoutSeconds = seconds
                        default:
                            guard let enabled = Bool(value) else { throw RuriError.message(Messages.CLILaunchSettingsCommands.commandsValueInvalid) }; commands.enabled = enabled
                        }
                        overrides.commands = commands
                    case .environment:
                        if args[2] == "environment-file" {
                            let file = URL(fileURLWithPath: value)
                            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                            let data = try handle.read(upToCount: 65537) ?? Data()
                            guard data.count <= 65536, let content = String(data: data, encoding: .utf8) else { throw RuriError.message(Messages.CLILaunchSettingsCommands.environmentFileInvalid) }
                            overrides.environment = content
                        } else { overrides.environment = value }
                    }
                }
                let effective = overrides.resolve(defaults: defaults); try effective.validate()
                if let index { state.instances[index].launchOverrides = overrides }
                else { state.settings.defaultLaunchSettings = effective }
            }
        }
        let state = try StateStore.load(paths)
        let overrides: InstanceLaunchOverrides
        if let id {
            guard let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CLILaunchSettingsCommands.instanceMissing) }
            overrides = instance.effectiveLaunchOverrides
        } else { overrides = .init(fixing: state.settings.defaultLaunchSettings) }
        let values = overrides.resolve(defaults: state.settings.defaultLaunchSettings)
        var memory: LaunchMemory?, memoryIssue: String?
        do { memory = try values.memoryPreview() } catch { memoryIssue = error.localizedDescription }
        struct Report: Encodable { let scope: String; let values: LaunchSettingsValues; let inherited: [String]; let memoryPreview: LaunchMemory?; let memoryIssue: String? }
        let report = Report(scope: scope, values: values, inherited: LaunchSettingKey.allCases.filter { overrides.inherits($0) }.map(\.rawValue), memoryPreview: memory, memoryIssue: memoryIssue)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    }
}
