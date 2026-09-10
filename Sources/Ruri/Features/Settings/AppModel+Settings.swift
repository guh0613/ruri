import Foundation
import RuriCore

extension AppModel {
    func updateDefaultLaunchSettings(_ draft: LaunchSettingsValues, basedOn original: LaunchSettingsValues) {
        var current = state.settings.defaultLaunchSettings
        func apply<Value: Equatable>(_ key: WritableKeyPath<LaunchSettingsValues, Value>) {
            if draft[keyPath: key] != original[keyPath: key] { current[keyPath: key] = draft[keyPath: key] }
        }
        apply(\.memory); apply(\.java); apply(\.jvmArguments); apply(\.gameArguments); apply(\.window); apply(\.presentation)
        state.settings.defaultLaunchSettings = current; save()
        Task { await scanJava() }
    }
    func applyNetworkSettings() async { await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic) }
}
