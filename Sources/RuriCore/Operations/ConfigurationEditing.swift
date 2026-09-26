import Foundation
import RuriLocalization

extension ConfigurationService {
    /// Save only fields edited in a GUI draft. Disjoint CLI edits survive; an
    /// edited field that changed since the draft opened remains a conflict.
    @discardableResult public func saveDefaults(_ draft: LaunchSettingsValues, basedOn original: LaunchSettingsValues) throws -> PersistentState {
        try draft.validate()
        return try StateStore.updateIfChanged(paths) { state in
            let value = try Self.mergeLaunch(draft, original: original, current: state.settings.defaultLaunchSettings)
            if value != state.settings.defaultLaunchSettings { state.settings.defaultLaunchSettings = value }
        }
    }

    @discardableResult public func saveInstanceSettings(_ draft: GameInstance, basedOn original: GameInstance) throws -> PersistentState {
        guard draft.id == original.id else { throw Self.editConflict("id") }
        try InstanceService.validateName(draft.name)
        if let image = draft.iconPNG { try InstanceIconImage.validate(image) }
        return try StateStore.updateIfChanged(paths) { state in
            guard let index = state.instances.firstIndex(where: { $0.id == draft.id }) else { throw Self.editConflict("id") }
            var current = state.instances[index]
            func edit<T: Equatable>(_ key: WritableKeyPath<GameInstance, T>, _ name: String) throws {
                current[keyPath: key] = try Self.mergeField(draft[keyPath: key], original: original[keyPath: key], current: current[keyPath: key], name: name)
            }
            try edit(\.name, "name"); try edit(\.favorite, "favorite")
            try edit(\.iconPNG, "iconPNG"); try edit(\.iconStyle, "iconStyle")
            let desired = draft.effectiveLaunchOverrides, baseline = original.effectiveLaunchOverrides
            var overrides = current.effectiveLaunchOverrides
            let defaults = state.settings.defaultLaunchSettings
            let draftValues = Self.launchValues(desired.resolve(defaults: defaults))
            let baselineValues = Self.launchValues(baseline.resolve(defaults: defaults))
            for group in LaunchSettingKey.allCases {
                let wasInherited = baseline.inherits(group), wantsInheritance = desired.inherits(group)
                if wasInherited == wantsInheritance && (wantsInheritance || draftValues[group.rawValue] == baselineValues[group.rawValue]) { continue }
                if wasInherited != wantsInheritance {
                    let currentValues = Self.launchValues(overrides.resolve(defaults: defaults))
                    let matchesOriginal = overrides.inherits(group) == wasInherited && (wasInherited || currentValues[group.rawValue] == baselineValues[group.rawValue])
                    let matchesDraft = overrides.inherits(group) == wantsInheritance && (wantsInheritance || currentValues[group.rawValue] == draftValues[group.rawValue])
                    guard matchesOriginal || matchesDraft else { throw Self.editConflict(group.rawValue) }
                    Self.copyGroup(group.rawValue, from: desired, into: &overrides)
                } else {
                    guard !overrides.inherits(group) else { throw Self.editConflict(group.rawValue) }
                    let merged = try Self.mergeLaunch(desired.resolve(defaults: defaults), original: baseline.resolve(defaults: defaults), current: overrides.resolve(defaults: defaults), group: group)
                    Self.copyGroup(group.rawValue, from: InstanceLaunchOverrides(fixing: merged), into: &overrides)
                }
            }
            try overrides.resolve(defaults: defaults).validate()
            if overrides != current.effectiveLaunchOverrides { current.launchOverrides = overrides }
            state.instances[index] = current
        }
    }
    private static func mergeLaunch(_ draft: LaunchSettingsValues, original: LaunchSettingsValues, current: LaunchSettingsValues, group: LaunchSettingKey? = nil) throws -> LaunchSettingsValues {
        let desired = launchValues(draft), baseline = launchValues(original)
        var values = launchValues(current)
        // Java is an enum: switching its case is one edit, not three unrelated
        // updates to mode, major and path.
        if group == nil || group == .java {
            values = replacing(values, key: "java", value: try mergeField(desired["java"], original: baseline["java"], current: values["java"], name: "java"))
        }
        for field in launchFields where !field.name.hasPrefix("java.") && (group == nil || field.name == group!.rawValue || field.name.hasPrefix(group!.rawValue + ".")) {
            values = replacing(values, key: field.name, value: try mergeField(get(desired, field.name), original: get(baseline, field.name), current: get(values, field.name), name: field.name))
        }
        let result = try decodeLaunch(values)
        if group == nil { try result.validate() }
        return result
    }
    private static func replacing(_ value: OperationValue, key: String, value replacement: OperationValue) -> OperationValue {
        var result = value; assign(&result, path: key.split(separator: ".").map(String.init), value: replacement); return result
    }
    private static func mergeField<T: Equatable>(_ desired: T, original: T, current: T, name: String) throws -> T {
        if desired == original { return current }
        guard current == original || current == desired else { throw editConflict(name) }
        return desired
    }
    private static func editConflict(_ field: String) -> OperationFailure {
        .init("STATE_CONFLICT", Messages.CLIInterface.te8a7227e2180.localized, retryable: true, details: .object(["field": .string(field)]))
    }
}
