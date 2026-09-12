import RuriLocalization
import SwiftUI
import Observation
import RuriCore

/// Keep the draft while navigating between settings categories or main pages.
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
    @Bindable var draft: DefaultLaunchSettingsDraft

    var body: some View {
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
    }
}
