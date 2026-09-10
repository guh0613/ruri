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
            SettingsLayout(title: "默认启动设置", subtitle: "供选择“跟随默认”的实例使用", panes: [.runtime, .launch, .advanced], selection: $pane) {
                LaunchSettingsEditor(overrides: $overrides, defaults: original, runtimes: model.runtimes, showsInheritance: false, keys: pane.launchKeys)
            }
            Divider()
            if let issue {
                Label(issue, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 12)
            }
            HStack {
                Text(hasChanges ? "有未保存的更改" : "已运行的游戏保持当前设置").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存默认设置", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!hasChanges || model.readOnly)
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
        else { issue = model.error ?? "无法保存默认设置。" }
    }
}
