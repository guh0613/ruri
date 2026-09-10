import SwiftUI
import AppKit
import RuriCore

struct MinecraftDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    let catalog: MinecraftDirectoryCatalog
    @State private var selectedID: String?
    @State private var search = ""
    private var selected: MinecraftDirectoryVersion? { catalog.versions.first { $0.id == selectedID } }
    private var filtered: [MinecraftDirectoryVersion] {
        catalog.versions.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
    }
    init(catalog: MinecraftDirectoryCatalog) {
        self.catalog = catalog
        _selectedID = State(initialValue: catalog.selectedVersionID ?? catalog.versions.first(where: { $0.issue == nil })?.id ?? catalog.versions.first?.id)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("已有 Minecraft 目录", systemImage: "folder.badge.gearshape").font(.title2.bold())
            Text(catalog.directory.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("搜索版本或加载器", text: $search).textFieldStyle(.roundedBorder)
                    List(filtered, selection: $selectedID) { version in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(version.id).font(.headline).lineLimit(2)
                                if version.issue != nil { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                            }
                            Text(version.issue == nil ? version.subtitle : "无法读取").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 4).tag(version.id)
                    }.listStyle(.inset)
                    Text("\(catalog.versions.count) 个版本").font(.caption).foregroundStyle(.secondary)
                }.frame(width: 230).padding(.trailing, 16)
                Divider()
                ScrollView {
                    if let selected {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(selected.id).font(.title3.bold()).textSelection(.enabled)
                            if let issue = selected.issue {
                                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                            } else {
                                Text(selected.subtitle).foregroundStyle(.secondary)
                                Text("存档、模组与游戏设置的位置").font(.headline)
                                ForEach(selected.gameLocations) { location in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Text(location.title).font(.headline)
                                            if location.id == selected.suggestedLocationID { Text("原配置").font(.caption).foregroundStyle(.secondary) }
                                            Spacer()
                                            Button {
                                                NSWorkspace.shared.activateFileViewerSelecting([location.directory])
                                            } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("在 Finder 中显示").disabled(!location.available)
                                        }
                                        Text(location.directory.path).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        Text(location.explanation).font(.caption).foregroundStyle(.secondary)
                                        Text(location.available ? (location.contents.isEmpty ? "未发现常见游戏数据" : "包含：" + location.contents.joined(separator: "、")) : "目录不可用")
                                            .font(.caption).foregroundStyle(location.available ? Color.secondary : .orange)
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                                }
                                ForEach(Array(selected.warnings.enumerated()), id: \.offset) { _, warning in
                                    Label(warning, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 18)
                    } else { Text("选择一个版本查看详情").foregroundStyle(.secondary).padding() }
                }
            }
            HStack {
                Text("查看已有版本及其游戏数据目录。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 760, height: 590)
        .onChange(of: search) { _, _ in
            if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
        }
    }
}
