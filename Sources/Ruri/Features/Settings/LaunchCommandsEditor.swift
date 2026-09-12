import RuriLocalization
import SwiftUI
import RuriCore

struct LaunchCommandsEditor: View {
    @Binding var commands: LaunchCommands
    var body: some View {
        Toggle(Messages.AppLaunchCommandsEditor.customLaunchCommand.localized, isOn: $commands.enabled)
        if commands.enabled || !commands.isEmpty {
            Group {
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.beforeLaunchCommand.localized,
                                 prompt: Messages.AppLaunchCommandsEditor.beforeLaunchPlaceholder.localized, text: $commands.before,
                                 help: Messages.AppLaunchCommandsEditor.beforeLaunchHelp.localized, showsTitle: true)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.afterLaunchCommand.localized,
                                 prompt: Messages.AppLaunchCommandsEditor.beforeLaunchPlaceholder.localized, text: $commands.after,
                                 help: Messages.AppLaunchCommandsEditor.afterLaunchHelp.localized, showsTitle: true)
                SettingsNumberField(title: Messages.AppLaunchCommandsEditor.commandTimeout.localized, value: $commands.timeoutSeconds, unit: Messages.AppLaunchCommandsEditor.seconds.localized)
                SettingsTextArea(title: Messages.AppLaunchCommandsEditor.wrapperCommand.localized,
                                 prompt: Messages.AppLaunchCommandsEditor.wrapperPlaceholder.localized, text: $commands.wrapper,
                                 help: Messages.AppLaunchCommandsEditor.wrapperHelp.localized, showsTitle: true)
            }.disabled(!commands.enabled)
            DisclosureGroup(Messages.AppLaunchCommandsEditor.variablesAndExamples.localized) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Messages.AppLaunchCommandsEditor.shellExecutionHelp.localized).foregroundStyle(.secondary)
                    Text(Messages.AppLaunchCommandsEditor.availableVariables.localized).textSelection(.enabled)
                    Text(Messages.AppLaunchCommandsEditor.wrapperPlaceholderHelp.localized).foregroundStyle(.secondary)
                }.font(.caption).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
            }
        }
    }
}
