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
        rebase(\.window); rebase(\.presentation); rebase(\.environment); rebase(\.commands)
        original = latest
        overrides = .init(fixing: draft)
    }
}

struct DefaultLaunchSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DefaultLaunchSettingsDraft

    init(settings: AppSettings) {
        _draft = State(initialValue: .init(values: settings.defaultLaunchSettings))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(Messages.AppPreferencesView.globalGameSettings.localized).font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
            ScrollViewReader { proxy in
                Form {
                    LaunchSettingsEditor(overrides: $draft.overrides, defaults: draft.original, runtimes: model.runtimes, showsInheritance: false,
                                         keys: [.java, .memory, .window, .presentation, .jvmArguments, .gameArguments, .environment, .commands])
                        .disabled(model.readOnly)
                }.formStyle(.grouped).scrollContentBackground(.hidden)
                    .onChange(of: draft.issue, initial: true) { _, issue in
                        if issue != nil, let failure = SettingsValidation.issue(in: draft.values) {
                            proxy.scrollTo(failure.key, anchor: .top)
                        }
                    }
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
        }.frame(width: 720, height: 670)
        .interactiveDismissDisabled(draft.hasChanges)
        .onChange(of: model.state.settings.defaultLaunchSettings) { _, latest in draft.synchronize(with: latest) }
    }

    private func save() {
        let values = draft.values
        if let failure = SettingsValidation.issue(in: values) {
            draft.issue = failure.message
            return
        }
        if model.updateDefaultLaunchSettings(values, basedOn: draft.original) { dismiss() }
        else { draft.issue = model.error ?? Messages.AppDefaultLaunchSettingsView.saveDefaultFailure.localized }
    }
}
