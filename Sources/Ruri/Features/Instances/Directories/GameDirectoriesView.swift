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
                Button("添加文件夹…", systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
                Button("管理文件夹…", systemImage: "folder.badge.gearshape") { model.showDirectories = true }
            } label: {
                Label(model.selectedDirectoryName, systemImage: "folder").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(model.busy)
            .help("选择要浏览和安装到的文件夹；运行中的游戏会继续受监控。")
        }
    }
    private func select(_ id: UUID) { model.selectDirectory(id) }
}

struct GameDirectoriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "实例文件夹", subtitle: "按整合包、游戏版本或磁盘整理你的实例。")
                Spacer()
                Button("添加文件夹…", systemImage: "plus") { model.chooseMinecraftDirectory() }.disabled(model.busy)
            }
            Text("添加已有 Minecraft 文件夹即可使用其中的版本，新建实例也保存在当前文件夹。切换文件夹不会结束正在运行的游戏。")
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
                            Button(model.selectedDirectoryID == GameDirectory.defaultID ? "已选择" : "选择") { model.selectDirectory(GameDirectory.defaultID) }
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
                    Button(model.selectedDirectoryID == directory.id ? "已选择" : "选择") { model.selectDirectory(directory.id) }
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
                        Button("取消登记") { model.changeDirectory { try GameDirectoryStore.remove(directory.id, paths: $0) } }.disabled(count > 0 && !directory.isMinecraft)
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
