import Foundation
import RuriCore

extension CLI {
    static func manageLaunchSettings(_ args: [String], paths: LauncherPaths) throws {
        let usage = "用法：launch-settings <defaults|实例UUID> [set <memory|java|jvmArguments|gameArguments|window> <值> | inherit <项目|all>]。内存单位 MB，Java 为 auto 或完整路径，窗口为 1600x900。默认只查看生效值与继承来源。"
        guard let scope = args.first, scope == "defaults" || UUID(uuidString: scope) != nil else { throw RuriError.message(usage) }
        let id = UUID(uuidString: scope)
        if args.count > 1 {
            guard (args.count == 4 && args[1] == "set") || (args.count == 3 && args[1] == "inherit" && id != nil) else { throw RuriError.message(usage) }
            let key = LaunchSettingKey(rawValue: args[2])
            guard key != nil || (args[1] == "inherit" && args[2] == "all") else { throw RuriError.message(usage) }
            try StateStore.update(paths) { state in
                let index = id.flatMap { id in state.instances.firstIndex { $0.id == id } }
                if id != nil && index == nil { throw RuriError.message("实例不存在。") }
                let defaults = state.settings.defaultLaunchSettings
                var overrides = index.map { state.instances[$0].effectiveLaunchOverrides } ?? .init(fixing: defaults)
                if args[1] == "inherit" {
                    if let key { overrides.setInheritance(true, for: key, defaults: defaults) } else { overrides = .init() }
                } else {
                    let value = args[3]
                    switch key! {
                    case .memory: guard let memory = Int(value) else { throw RuriError.message(usage) }; overrides.memoryMB = memory
                    case .java: overrides.java = value == "auto" ? .automatic : .path(value)
                    case .jvmArguments: overrides.jvmArguments = value
                    case .gameArguments: overrides.gameArguments = value
                    case .window:
                        let parts = value.lowercased().split(separator: "x")
                        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { throw RuriError.message(usage) }
                        overrides.window = .init(width: width, height: height)
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
            guard let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message("实例不存在。") }
            overrides = instance.effectiveLaunchOverrides
        } else { overrides = .init(fixing: state.settings.defaultLaunchSettings) }
        struct Report: Encodable { let scope: String; let values: LaunchSettingsValues; let inherited: [String] }
        let report = Report(scope: scope, values: overrides.resolve(defaults: state.settings.defaultLaunchSettings), inherited: LaunchSettingKey.allCases.filter { overrides.inherits($0) }.map(\.rawValue))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    }
}
