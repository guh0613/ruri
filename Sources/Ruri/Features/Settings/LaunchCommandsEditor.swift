import RuriLocalization
import SwiftUI
import RuriCore

struct LaunchCommandsEditor: View {
    @Binding var commands: LaunchCommands
    var body: some View {
        Toggle(Messages.AppLaunchCommandsEditor.bodyText1.localized, isOn: $commands.enabled)
        if commands.enabled || !commands.isEmpty {
            Group {
                Text(Messages.AppLaunchCommandsEditor.bodyText2.localized).font(.headline)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.bodyText2.localized, prompt: Messages.AppLaunchCommandsEditor.bodyText3.localized, text: $commands.before)
                Text(Messages.AppLaunchCommandsEditor.bodyText4.localized).font(.caption).foregroundStyle(.secondary)
                Text(Messages.AppLaunchCommandsEditor.bodyText5.localized).font(.headline)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.bodyText5.localized, prompt: Messages.AppLaunchCommandsEditor.bodyText3.localized, text: $commands.after)
                Text(Messages.AppLaunchCommandsEditor.bodyText6.localized).font(.caption).foregroundStyle(.secondary)
                SettingsNumberField(title: Messages.AppLaunchCommandsEditor.bodyText7.localized, value: $commands.timeoutSeconds, unit: Messages.AppLaunchCommandsEditor.bodyText8.localized)
                Text(Messages.AppLaunchCommandsEditor.bodyText9.localized).font(.headline)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.bodyText9.localized, prompt: Messages.AppLaunchCommandsEditor.bodyText10.localized, text: $commands.wrapper)
                Text(Messages.AppLaunchCommandsEditor.bodyText11.localized).font(.caption).foregroundStyle(.secondary)
            }.disabled(!commands.enabled)
            DisclosureGroup(Messages.AppLaunchCommandsEditor.bodyText12.localized) {
                Text(Messages.AppLaunchCommandsEditor.bodyText13.localized).font(.caption).foregroundStyle(.secondary)
                Text(#"printf '%s\n' "$RURI_GAME_DIRECTORY""#).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(Messages.AppLaunchCommandsEditor.bodyText14.localized).font(.caption).textSelection(.enabled)
                Text(Messages.AppLaunchCommandsEditor.bodyText15.localized).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
