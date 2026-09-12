import RuriLocalization
import SwiftUI
import RuriCore

enum InstanceSettingsPane: String, CaseIterable, Identifiable {
    case overview, runtime, launch, advanced, files
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: Messages.AppSettingsLayout.overview.localized
        case .runtime: Messages.AppSettingsLayout.javaAndMemory.localized
        case .launch: Messages.AppSettingsLayout.windowAndLaunch.localized
        case .advanced: Messages.AppSettingsLayout.argumentsAndEnvironment.localized
        case .files: Messages.AppSettingsLayout.filesAndDirectories.localized
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
        case .overview: Messages.AppSettingsLayout.overviewDetails.localized
        case .runtime: Messages.AppSettingsLayout.javaAndMemoryDetails.localized
        case .launch: Messages.AppSettingsLayout.windowAndLaunchDetails.localized
        case .advanced: Messages.AppSettingsLayout.argumentsAndEnvironmentDetails.localized
        case .files: Messages.AppSettingsLayout.filesAndDirectoriesDetails.localized
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
                }.listStyle(.sidebar).scrollContentBackground(.hidden).accessibilityLabel(Messages.AppSettingsLayout.settingsCategory.localized)
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
    var help: String? = nil
    var showsTitle = false
    @FocusState private var isFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle { Text(title).fontWeight(.medium) }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text).scrollContentBackground(.hidden)
                    .font(.system(.body, design: .monospaced)).multilineTextAlignment(.leading).padding(6)
                    .autocorrectionDisabled().focused($isFocused).accessibilityLabel(title)
                if text.isEmpty {
                    Text(prompt).font(.system(.body, design: .monospaced)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false).accessibilityHidden(true)
                }
            }.frame(height: 88).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: isFocused ? 2 : 1).allowsHitTesting(false))
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
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
