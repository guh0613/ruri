import RuriLocalization
import SwiftUI
import Observation
import RuriCore

/// Keep edits local to the sheet and merge updates to untouched settings.
@MainActor @Observable final class DefaultLaunchSettingsDraft {
    private(set) var original: LaunchSettingsValues
    var overrides: InstanceLaunchOverrides {
        didSet { issue = nil }
    }
    var issue: String?
    var values: LaunchSettingsValues { overrides.resolve(defaults: original) }
    var hasChanges: Bool { values != original }

    init(values: LaunchSettingsValues) {
        original = values
        overrides = .init(fixing: values)
    }
    func reset(to values: LaunchSettingsValues) {
        original = values
        overrides = .init(fixing: values)
        issue = nil
    }
    func synchronize(with latest: LaunchSettingsValues) {
        guard latest != original else { return }
        var draft = values
        func rebase<Value: Equatable>(_ key: WritableKeyPath<LaunchSettingsValues, Value>) {
            if draft[keyPath: key] == original[keyPath: key] { draft[keyPath: key] = latest[keyPath: key] }
        }
        rebase(\.memory); rebase(\.java); rebase(\.jvmArguments); rebase(\.gameArguments)
        rebase(\.window); rebase(\.presentation); rebase(\.environment); rebase(\.commands); rebase(\.macOS)
        original = latest
        overrides = .init(fixing: draft)
    }
}

struct DefaultLaunchSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DefaultLaunchSettingsDraft
    @State private var pane = InstanceSettingsPane.runtime

    init(settings: AppSettings) {
        _draft = State(initialValue: .init(values: settings.defaultLaunchSettings))
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsLayout(title: Messages.AppDefaultLaunchSettingsView.defaultLaunchSettings.localized,
                           subtitle: Messages.AppDefaultLaunchSettingsView.followsDefaultHelp.localized,
                           panes: [.runtime, .launch, .advanced], selection: $pane) {
                LaunchSettingsEditor(overrides: $draft.overrides, defaults: draft.original, runtimes: model.runtimes, showsInheritance: false, keys: pane.launchKeys)
                    .disabled(model.readOnly)
            }
            Divider()
            if let issue = draft.issue {
                Label(issue, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 12)
            }
            HStack(spacing: 12) {
                if draft.hasChanges {
                    Text(Messages.AppDefaultLaunchSettingsView.unsavedChanges.localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppDefaultLaunchSettingsView.saveDefaultSettings.localized, action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!draft.hasChanges || model.readOnly)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 860, height: 670)
        .interactiveDismissDisabled(draft.hasChanges)
        .onChange(of: model.state.settings.defaultLaunchSettings) { _, latest in draft.synchronize(with: latest) }
    }

    private func save() {
        let values = draft.values
        if let failure = SettingsValidation.issue(in: values) {
            pane = .containing(failure.key)
            draft.issue = failure.message
            return
        }
        if model.updateDefaultLaunchSettings(values, basedOn: draft.original) { dismiss() }
        else { draft.issue = model.error ?? Messages.AppDefaultLaunchSettingsView.saveDefaultFailure.localized }
    }
}
