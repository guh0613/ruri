import Foundation
import RuriCore

extension AppModel {
    @discardableResult func updateDefaultLaunchSettings(_ draft: LaunchSettingsValues, basedOn original: LaunchSettingsValues) -> Bool {
        guard !readOnly else { return false }
        var current = state.settings.defaultLaunchSettings
        func apply<Value: Equatable>(_ key: WritableKeyPath<LaunchSettingsValues, Value>) {
            if draft[keyPath: key] != original[keyPath: key] { current[keyPath: key] = draft[keyPath: key] }
        }
        apply(\.memory); apply(\.java); apply(\.jvmArguments); apply(\.gameArguments); apply(\.window); apply(\.presentation); apply(\.environment)
        state.settings.defaultLaunchSettings = current; save()
        Task { await scanJava() }
        return !readOnly
    }
    func applyNetworkSettings() async { await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic) }
}
