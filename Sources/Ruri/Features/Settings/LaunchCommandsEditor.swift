import RuriLocalization
import SwiftUI
import RuriCore

struct LaunchCommandsEditor: View {
    @Binding var commands: LaunchCommands
    var body: some View {
        Toggle(Messages.AppLaunchCommandsEditor.customLaunchCommand.localized, isOn: $commands.enabled)
        if commands.enabled || !commands.isEmpty {
            Group {
                Text(Messages.AppLaunchCommandsEditor.beforeLaunchCommand.localized).font(.headline)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.beforeLaunchCommand.localized, prompt: Messages.AppLaunchCommandsEditor.beforeLaunchPlaceholder.localized, text: $commands.before)
                Text(Messages.AppLaunchCommandsEditor.beforeLaunchHelp.localized).font(.caption).foregroundStyle(.secondary)
                Text(Messages.AppLaunchCommandsEditor.afterLaunchCommand.localized).font(.headline)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.afterLaunchCommand.localized, prompt: Messages.AppLaunchCommandsEditor.beforeLaunchPlaceholder.localized, text: $commands.after)
                Text(Messages.AppLaunchCommandsEditor.afterLaunchHelp.localized).font(.caption).foregroundStyle(.secondary)
                SettingsNumberField(title: Messages.AppLaunchCommandsEditor.commandTimeout.localized, value: $commands.timeoutSeconds, unit: Messages.AppLaunchCommandsEditor.seconds.localized)
                Text(Messages.AppLaunchCommandsEditor.wrapperCommand.localized).font(.headline)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.wrapperCommand.localized, prompt: Messages.AppLaunchCommandsEditor.wrapperPlaceholder.localized, text: $commands.wrapper)
                Text(Messages.AppLaunchCommandsEditor.wrapperHelp.localized).font(.caption).foregroundStyle(.secondary)
            }.disabled(!commands.enabled)
            DisclosureGroup(Messages.AppLaunchCommandsEditor.variablesAndExamples.localized) {
                Text(Messages.AppLaunchCommandsEditor.shellExecutionHelp.localized).font(.caption).foregroundStyle(.secondary)
                Text(#"printf '%s\n' "$RURI_GAME_DIRECTORY""#).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(Messages.AppLaunchCommandsEditor.availableVariables.localized).font(.caption).textSelection(.enabled)
                Text(Messages.AppLaunchCommandsEditor.wrapperPlaceholderHelp.localized).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
