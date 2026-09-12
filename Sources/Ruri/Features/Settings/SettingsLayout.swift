import RuriLocalization
import SwiftUI
import RuriCore

enum InstanceSettingsPane: String, CaseIterable, Identifiable {
    case overview, runtime, launch, advanced, files
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: Messages.AppSettingsLayout.titleText1.localized
        case .runtime: Messages.AppSettingsLayout.titleText2.localized
        case .launch: Messages.AppSettingsLayout.titleText3.localized
        case .advanced: Messages.AppSettingsLayout.titleText4.localized
        case .files: Messages.AppSettingsLayout.titleText5.localized
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .runtime: "memorychip"
        case .launch: "macwindow"
        case .advanced: "terminal"
        case .files: "folder"
        }
    }
    var detail: String {
        switch self {
        case .overview: Messages.AppSettingsLayout.detailText1.localized
        case .runtime: Messages.AppSettingsLayout.detailText2.localized
        case .launch: Messages.AppSettingsLayout.detailText3.localized
        case .advanced: Messages.AppSettingsLayout.detailText4.localized
        case .files: Messages.AppSettingsLayout.detailText5.localized
        }
    }
    var launchKeys: [LaunchSettingKey] {
        switch self {
        case .runtime: [.java, .memory]
        case .launch: [.window, .presentation]
        case .advanced: [.jvmArguments, .gameArguments, .environment, .commands]
        default: []
        }
    }
    static func containing(_ key: LaunchSettingKey) -> Self {
        allCases.first { $0.launchKeys.contains(key) } ?? .runtime
    }
}

struct SettingsLayout<Content: View>: View {
    let title: String
    let subtitle: String
    var panes = InstanceSettingsPane.allCases
    @Binding var selection: InstanceSettingsPane
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 8)
                List(panes, selection: $selection) { pane in
                    Label(pane.title, systemImage: pane.symbol).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.vertical, 6).tag(pane)
                }.listStyle(.sidebar).scrollContentBackground(.hidden).accessibilityLabel(Messages.AppSettingsLayout.bodyText1.localized)
            }.frame(width: 180).background(.thinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.title).font(.title2.weight(.semibold))
                    Text(selection.detail).font(.callout).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
                Form { content }.formStyle(.grouped).id(selection)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SettingsNumberField: View {
    let title: String
    @Binding var value: Int
    var unit = "MB"
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number.grouping(.never))
                    .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 88)
                    .accessibilityLabel(title)
                Text(unit).foregroundStyle(.secondary).frame(minWidth: 22, alignment: .leading)
            }
        }.accessibilityElement(children: .contain)
    }
}

struct SettingsTextArea: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text).scrollContentBackground(.hidden)
                    .font(.system(.body, design: .monospaced)).padding(6)
                    .accessibilityLabel(title)
                if text.isEmpty {
                    Text(prompt).font(.system(.body, design: .monospaced)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false).accessibilityHidden(true)
                }
            }.frame(height: 82).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.16)))
        }.padding(.vertical, 5)
    }
}

struct SettingsActionRow: View {
    let title: String
    let detail: String
    let button: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(button, action: action).accessibilityLabel(title + "，" + button)
        }.padding(.vertical, 3)
    }
}

enum SettingsValidation {
    static func issue(in values: LaunchSettingsValues) -> (key: LaunchSettingKey, message: String)? {
        for key in LaunchSettingKey.allCases {
            var field = LaunchSettingsValues()
            switch key {
            case .memory: field.memory = values.memory
            case .java: field.java = values.java
            case .jvmArguments: field.jvmArguments = values.jvmArguments; field.memory = values.memory
            case .gameArguments: field.gameArguments = values.gameArguments
            case .window: field.window = values.window
            case .presentation: field.presentation = values.presentation
            case .environment: field.environment = values.environment
            case .commands: field.commands = values.commands
            }
            do { try field.validate() }
            catch { return (key, error.localizedDescription) }
        }
        return nil
    }
}
