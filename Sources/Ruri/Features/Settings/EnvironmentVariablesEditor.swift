import RuriLocalization
import SwiftUI
import RuriCore

struct EnvironmentVariablesEditor: View {
    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
        var removes: Bool
    }
    @Binding var text: String
    @State private var rows: [Row]
    init(text: Binding<String>) {
        _text = text; _rows = State(initialValue: Self.decode(text.wrappedValue))
    }
    private static func decode(_ text: String) -> [Row] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n").map { line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return Row(name: String(parts[0]), value: parts.count == 2 ? String(parts[1]) : "", removes: parts.count == 1)
        }
    }
    private var encoded: String { rows.map { $0.name + ($0.removes ? "" : "=" + $0.value) }.joined(separator: "\n") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                Text(Messages.AppEnvironmentVariablesEditor.noCustomVariables.localized).font(.subheadline)
                Text(Messages.AppEnvironmentVariablesEditor.variableHint.localized).font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(Messages.AppEnvironmentVariablesEditor.variableName.localized).frame(width: 145, alignment: .leading)
                    Text(Messages.AppEnvironmentVariablesEditor.valueColumn.localized).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Messages.AppEnvironmentVariablesEditor.actions.localized).frame(width: 74, alignment: .leading)
                    Color.clear.frame(width: 22, height: 1)
                }.font(.caption).foregroundStyle(.secondary)
                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField(Messages.AppEnvironmentVariablesEditor.variableName.localized, text: $row.name, prompt: Text(Messages.AppEnvironmentVariablesEditor.name.localized)).labelsHidden().multilineTextAlignment(.leading).frame(width: 145).accessibilityLabel(Messages.AppEnvironmentVariablesEditor.variableName.localized)
                        TextField(Messages.AppEnvironmentVariablesEditor.variableValue.localized, text: $row.value, prompt: Text(row.removes ? Messages.AppEnvironmentVariablesEditor.removeInheritedValue.localized : Messages.AppEnvironmentVariablesEditor.enterValue.localized)).labelsHidden().multilineTextAlignment(.leading).disabled(row.removes).accessibilityLabel(Messages.AppEnvironmentVariablesEditor.variableValue.localized)
                        Picker(Messages.AppEnvironmentVariablesEditor.actions.localized, selection: $row.removes) { Text(Messages.AppEnvironmentVariablesEditor.setVariable.localized).tag(false); Text(Messages.AppEnvironmentVariablesEditor.removeVariable.localized).tag(true) }.labelsHidden().frame(width: 74).accessibilityLabel(Messages.AppEnvironmentVariablesEditor.variableActions.localized)
                        Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).frame(width: 22).help(Messages.AppEnvironmentVariablesEditor.deleteConfiguration.localized).accessibilityLabel(Messages.AppEnvironmentVariablesEditor.deleteVariable.localized)
                    }.textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                }
            }
            Button(Messages.AppEnvironmentVariablesEditor.addVariable.localized, systemImage: "plus") { rows.append(Row(name: "", value: "", removes: false)) }
            if case .failure(let error) = Result(catching: { try LaunchEnvironment(text) }), !rows.contains(where: { $0.name.isEmpty }) {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
            Text(Messages.AppEnvironmentVariablesEditor.valuePassthroughNotice.localized).font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(Messages.AppEnvironmentVariablesEditor.usageGuide.localized) {
                Text(Messages.AppEnvironmentVariablesEditor.nameValidation.localized).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
        .onChange(of: rows) { _, _ in text = encoded }
        .onChange(of: text) { _, value in if value != encoded { rows = Self.decode(value) } }
    }
}
