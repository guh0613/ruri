import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct DefaultLaunchSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var overrides: InstanceLaunchOverrides
    @State private var issue: String?
    @State private var pane = InstanceSettingsPane.runtime
    private let original: LaunchSettingsValues
    init(settings: AppSettings) {
        original = settings.defaultLaunchSettings
        _overrides = State(initialValue: .init(fixing: settings.defaultLaunchSettings))
    }
    var body: some View {
        VStack(spacing: 0) {
            SettingsLayout(title: Messages.AppDefaultLaunchSettingsView.bodyText1.localized, subtitle: Messages.AppDefaultLaunchSettingsView.bodyText2.localized, panes: [.runtime, .launch, .advanced], selection: $pane) {
                LaunchSettingsEditor(overrides: $overrides, defaults: original, runtimes: model.runtimes, showsInheritance: false, keys: pane.launchKeys)
            }
            Divider()
            if let issue {
                Label(issue, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 12)
            }
            HStack {
                Text(hasChanges ? Messages.AppDefaultLaunchSettingsView.issueText1.localized : Messages.AppDefaultLaunchSettingsView.issueText2.localized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppDefaultLaunchSettingsView.issueText3.localized, action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!hasChanges || model.readOnly)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 860, height: 670)
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: overrides) { _, _ in issue = nil }
    }
    private var hasChanges: Bool { overrides.resolve(defaults: original) != original }
    private func save() {
        let values = overrides.resolve(defaults: original)
        if let failure = SettingsValidation.issue(in: values) { pane = .containing(failure.key); issue = failure.message; return }
        if model.updateDefaultLaunchSettings(values, basedOn: original) { dismiss() }
        else { issue = model.error ?? Messages.AppDefaultLaunchSettingsView.failureText1.localized }
    }
}
