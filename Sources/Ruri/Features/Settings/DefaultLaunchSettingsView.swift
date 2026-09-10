import SwiftUI
import AppKit
import RuriCore

struct DefaultLaunchSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var overrides: InstanceLaunchOverrides
    @State private var issue: String?
    private let original: LaunchSettingsValues
    init(settings: AppSettings) {
        original = settings.defaultLaunchSettings
        _overrides = State(initialValue: .init(fixing: settings.defaultLaunchSettings))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "默认启动设置", subtitle: "用于跟随默认设置的项目；已运行的游戏保持本次启动时的值。")
            Text("新建实例默认继承。旧实例和导入实例保留原值，可在实例设置中按项恢复默认。").font(.callout).foregroundStyle(.secondary)
            Form { LaunchSettingsEditor(overrides: $overrides, defaults: original, runtimes: model.runtimes, showsInheritance: false) }.formStyle(.grouped)
            if let issue { Text(issue).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存默认设置") {
                    do { let values = overrides.resolve(defaults: original); try values.validate(); model.updateDefaultLaunchSettings(values, basedOn: original); dismiss() }
                    catch { issue = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620, height: 590)
    }
}
