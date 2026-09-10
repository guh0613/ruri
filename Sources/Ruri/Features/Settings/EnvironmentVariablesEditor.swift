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
                Text("没有自定义环境变量").font(.subheadline)
                Text("仅在模组或工具要求时添加，通常无需填写。").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("变量名称").frame(width: 145, alignment: .leading)
                    Text("值").frame(maxWidth: .infinity, alignment: .leading)
                    Text("操作").frame(width: 74, alignment: .leading)
                    Color.clear.frame(width: 22, height: 1)
                }.font(.caption).foregroundStyle(.secondary)
                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField("变量名称", text: $row.name, prompt: Text("名称")).labelsHidden().multilineTextAlignment(.leading).frame(width: 145).accessibilityLabel("变量名称")
                        TextField("变量值", text: $row.value, prompt: Text(row.removes ? "移除继承值" : "输入值，可留空")).labelsHidden().multilineTextAlignment(.leading).disabled(row.removes).accessibilityLabel("变量值")
                        Picker("操作", selection: $row.removes) { Text("设置").tag(false); Text("移除").tag(true) }.labelsHidden().frame(width: 74).accessibilityLabel("环境变量操作")
                        Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).frame(width: 22).help("删除此项配置").accessibilityLabel("删除环境变量")
                    }.textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                }
            }
            Button("添加变量", systemImage: "plus") { rows.append(Row(name: "", value: "", removes: false)) }
            if case .failure(let error) = Result(catching: { try LaunchEnvironment(text) }), !rows.contains(where: { $0.name.isEmpty }) {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
            Text("值原样传给游戏，无需引号。选择“移除”可取消从系统继承的变量。").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("使用说明") {
                Text("名称只能包含字母、数字和下划线，不能以数字开头。Java 相关变量由 Ruri 管理，请使用 Java 或 JVM 参数设置。本机环境配置不会写入导出的整合包。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
        .onChange(of: rows) { _, _ in text = encoded }
        .onChange(of: text) { _, value in if value != encoded { rows = Self.decode(value) } }
    }
}
