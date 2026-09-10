import SwiftUI
import AppKit
import RuriCore

struct DirectorySidebarPicker: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("实例文件夹").font(.caption).foregroundStyle(.secondary)
            Menu {
                Button("默认实例文件夹") { select(GameDirectory.defaultID) }
                ForEach(model.state.gameDirectories ?? []) { directory in
                    Button(directory.name) { select(directory.id) }
                }
                Divider()
                Button("管理文件夹…", systemImage: "folder.badge.gearshape") { model.showDirectories = true }
            } label: {
                Label(model.selectedDirectoryName, systemImage: "folder").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(model.busy)
            .help("选择要浏览和安装到的文件夹；运行中的游戏会继续受监控。")
        }
    }
    private func select(_ id: UUID) { model.changeDirectory { try GameDirectoryStore.select(id, paths: $0) }; model.page = .library }
}

struct GameDirectoriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "实例文件夹", subtitle: "按整合包、游戏版本或磁盘整理你的实例。")
                Spacer()
                Button("添加文件夹…", systemImage: "plus") { adding = true }.disabled(model.busy)
            }
            Text("每个文件夹保存自己的实例、模组、存档和运行记录。Java 与可复用游戏资源在公共数据目录共享。切换文件夹不会结束正在运行的游戏。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    Surface {
                        HStack(alignment: .top) {
                            Image(systemName: "internaldrive").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("默认实例文件夹").font(.headline)
                                Text(model.basePaths.instances.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                Text("\(model.state.instances.filter { $0.directoryID == nil || $0.directoryID == GameDirectory.defaultID }.count) 个实例").font(.caption)
                            }
                            Spacer()
                            Button(model.selectedDirectoryID == GameDirectory.defaultID ? "已选择" : "选择") { model.changeDirectory { try GameDirectoryStore.select(GameDirectory.defaultID, paths: $0) } }
                                .disabled(model.busy || model.selectedDirectoryID == GameDirectory.defaultID)
                        }
                    }
                    ForEach(model.state.gameDirectories ?? []) { directory in GameDirectoryRow(directory: directory) }
                }.padding(2)
            }
            HStack {
                Button("重新检查可用性", systemImage: "arrow.clockwise") { Task { await model.refreshDirectoryAvailability() } }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 690, height: 560)
        .task { await model.refreshDirectoryAvailability() }
        .sheet(isPresented: $adding) { AddGameDirectoryView() }
    }
}

private struct GameDirectoryRow: View {
    @Environment(AppModel.self) private var model
    let directory: GameDirectory
    @State private var name: String
    init(directory: GameDirectory) { self.directory = directory; _name = State(initialValue: directory.name) }
    private var count: Int { model.state.instances.filter { $0.directoryID == directory.id }.count }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "folder").font(.title2)
                    TextField("文件夹名称", text: $name).textFieldStyle(.roundedBorder).onSubmit(rename)
                    if name != directory.name { Button("保存名称", action: rename).disabled(model.busy) }
                    Spacer()
                    Button(model.selectedDirectoryID == directory.id ? "已选择" : "选择") { model.changeDirectory { try GameDirectoryStore.select(directory.id, paths: $0) } }
                        .disabled(model.busy || model.selectedDirectoryID == directory.id)
                }
                Text(directory.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Label(model.directoryErrors[directory.id] == nil ? "\(count) 个实例 · 可用" : "\(count) 个实例 · 无法访问", systemImage: model.directoryErrors[directory.id] == nil ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(model.directoryErrors[directory.id] == nil ? Color.secondary : .orange)
                    Spacer()
                    Button("在 Finder 中显示") { do { try directory.validateAvailability(); NSWorkspace.shared.open(directory.url) } catch { model.error = error.localizedDescription } }
                    Menu {
                        Button("重新定位原文件夹…") { relocate() }
                        Button("取消登记") { model.changeDirectory { try GameDirectoryStore.remove(directory.id, paths: $0) } }.disabled(count > 0)
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                }
                if let issue = model.directoryErrors[directory.id] { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: directory.name) { name = directory.name }
    }
    private func rename() { model.changeDirectory { try GameDirectoryStore.rename(directory.id, name: name, paths: $0) } }
    private func relocate() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "选择“\(directory.name)”原文件夹的新位置。Ruri 会核对目录身份，文件不会被移动。"; panel.prompt = "重新定位"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.changeDirectory { try GameDirectoryStore.relocate(directory.id, to: url, paths: $0) }
    }
}

private struct AddGameDirectoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加实例文件夹").font(.title2.weight(.semibold))
            Text("选择或新建一个空文件夹。已有其他启动器的游戏数据，请先通过“导入”入口预览。这里不会搬动现有实例。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("显示名称", text: $name).textFieldStyle(.roundedBorder)
            HStack { Text(url?.path ?? "尚未选择文件夹").font(.caption).textSelection(.enabled); Spacer(); Button("选择文件夹…", action: choose) }
            HStack {
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("添加并选择") {
                    guard let url else { return }
                    model.changeDirectory { try GameDirectoryStore.add(name: name, url: url, paths: $0) }
                    if model.state.gameDirectories?.contains(where: { $0.url == url.standardizedFileURL.resolvingSymlinksInPath() }) == true { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(url == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
        }.padding(24).frame(width: 520)
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "选择文件夹"
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        url = selected; if name.isEmpty { name = selected.lastPathComponent }
    }
}
