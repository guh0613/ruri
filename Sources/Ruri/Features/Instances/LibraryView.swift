import SwiftUI
import AppKit
import RuriCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var deleteTarget: GameInstance?
    var filtered: [GameInstance] { model.directoryInstances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.gameVersion.contains(search) }.sorted { $0.favorite != $1.favorite ? $0.favorite : $0.createdAt > $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: model.selectedDirectoryName, subtitle: "\(model.directoryInstances.count) 个实例 · 在实例设置中查看运行目录。")
                    Spacer()
                    Button("导入…", systemImage: "square.and.arrow.down") { model.chooseInstanceImport() }.disabled(model.busy)
                    Button("新建实例", systemImage: "plus") { model.showCreate = true }.buttonStyle(.borderedProminent).disabled(model.busy)
                }
                TextField("搜索实例或版本", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 330)
                if let issue = model.directoryErrors[model.selectedDirectoryID] {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("实例文件夹无法访问", systemImage: "externaldrive.badge.exclamationmark").font(.headline)
                        Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack { Button("重新检查") { Task { await model.refreshDirectoryAvailability() } }; Button("管理文件夹…") { model.showDirectories = true } }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if filtered.isEmpty {
                    EmptyPanel(symbol: "square.stack.3d.up", title: model.directoryInstances.isEmpty ? "这个文件夹还没有实例" : "没有匹配的实例", detail: "创建一个游戏实例，或导入你喜爱的整合包。")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 18)], spacing: 18) {
                    ForEach(filtered) { instance in
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    InstanceIcon(loader: instance.loader)
                                    Spacer()
                                    if instance.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                                    Menu {
                                        Button("设为首页实例") { model.select(instance) }
                                        Button(instance.favorite ? "取消收藏" : "收藏") { var value = instance; value.favorite.toggle(); model.update(value) }
                                        Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
                                        Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
                                        Button("管理模组与资源包", systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
                                        Button("管理存档与备份", systemImage: "globe") { model.worldInstance = instance }
                                        if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                                            Button("恢复实例复制…", systemImage: "arrow.counterclockwise") { model.copyingInstance = instance }.disabled(model.busy)
                                        } else {
                                            Button("复制实例…", systemImage: "plus.square.on.square") { model.copyingInstance = instance }.disabled(model.busy || model.isInstanceInUse(instance.id))
                                        }
                                        Button("导出实例…", systemImage: "square.and.arrow.up") { model.exportingInstance = instance }.disabled(model.busy || model.isInstanceInUse(instance.id) || !instance.installed)
                                        if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                                            Button("恢复实例移动…", systemImage: "arrow.counterclockwise") { model.movingInstance = instance }.disabled(model.busy)
                                        } else {
                                            Button("移动到其他文件夹…", systemImage: "folder.badge.arrow.forward") { model.movingInstance = instance }.disabled(model.busy || model.isInstanceInUse(instance.id))
                                        }
                                        Button("修复游戏文件") { model.repair(instance) }.disabled(model.busy || model.isInstanceInUse(instance.id) || !instance.installed)
                                        Divider()
                                        Button("移到废纸篓", role: .destructive) { deleteTarget = instance }.disabled(model.busy || model.isInstanceInUse(instance.id))
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(instance.name).font(.headline).lineLimit(1)
                                    Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                HStack { TagPill(text: model.runningLabel(instance.id) ?? (instance.installed ? "就绪" : "待安装")); Spacer(); Text(memoryLabel(instance)).font(.caption).foregroundStyle(.secondary) }
                                Divider()
                                HStack {
                                    Button { model.editingInstance = instance } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).help("实例设置")
                                    Spacer()
                                    LaunchButton(instance: instance)
                                }
                            }
                        }
                    }
                }
            }.padding(30)
        }
        .confirmationDialog("将实例移到废纸篓？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { if let target = deleteTarget { model.trash(target) }; deleteTarget = nil }
        } message: { Text((deleteTarget?.runDirectory ?? .isolated) != .isolated ? "此实例的版本清单和运行记录会移入废纸篓。所选运行目录中的存档、模组、备份和游戏设置会保留。" : "实例的存档和模组会一起移入废纸篓。共享游戏文件会保留。") }
        .task(id: model.selectedDirectoryID) { await model.refreshDirectoryAvailability() }
    }
    private func memoryLabel(_ instance: GameInstance) -> String {
        guard let memory = try? instance.resolvedLaunchSettings(defaults: model.state.settings).memoryPreview() else { return "内存设置待检查" }
        return "\(memory.maximumMB) MB" + (memory.maximumSource == .automatic ? " · 自动" : memory.maximumSource == .jvmArguments ? " · 参数" : "")
    }
}
