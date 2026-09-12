import SwiftUI
import AppKit
import RuriCore

/// Every instance in the selected folder, as a grid of cards or a list of
/// rows. The folder and count sit under the window title like a Finder
/// window, and the folder, layout, import and create controls are all icons
/// in the toolbar.
struct LibraryView: View {
    enum Layout: String { case grid, list }
    @Environment(AppModel.self) private var model
    @AppStorage("libraryLayout") private var layout = Layout.grid
    @State private var search = ""
    @State private var deleteTarget: GameInstance?
    private var filtered: [GameInstance] {
        model.directoryInstances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.gameVersion.contains(search) }
            .sorted { $0.favorite != $1.favorite ? $0.favorite : $0.createdAt > $1.createdAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let issue = model.directoryErrors[model.selectedDirectoryID] {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("实例文件夹无法访问", systemImage: "externaldrive.badge.exclamationmark").font(.headline)
                        Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack { Button("重新检查") { Task { await model.refreshDirectoryAvailability() } }; Button("管理文件夹…") { model.showDirectories = true } }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if model.paths.isMinecraftDirectory(model.selectedDirectoryID) {
                    RepositoryImportRecoveryView(directoryID: model.selectedDirectoryID)
                }
                if model.directoryInstances.isEmpty {
                    emptyFolder
                } else if filtered.isEmpty {
                    EmptyPanel(symbol: "magnifyingglass", title: "没有匹配的实例", detail: "换个名称或版本号试试。")
                } else if layout == .grid {
                    grid
                } else {
                    list
                }
            }.padding(28)
        }
        .navigationSubtitle("\(model.selectedDirectoryName) · \(countLabel)")
        .searchable(text: $search, placement: .toolbar, prompt: "搜索实例或版本")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                DirectoryMenu()
                Picker("布局", selection: $layout) {
                    Label("网格", systemImage: "square.grid.2x2").tag(Layout.grid)
                    Label("列表", systemImage: "list.bullet").tag(Layout.list)
                }.pickerStyle(.segmented).help("网格或列表")
                Menu {
                    Button("导入实例或整合包…", systemImage: "square.and.arrow.down") { model.chooseInstanceImport() }
                    Button("添加游戏文件夹…", systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
                } label: { Label("导入", systemImage: "square.and.arrow.down") }.help("导入实例、整合包或游戏文件夹").disabled(model.busy)
                Button { model.showCreate = true } label: { Label("新建实例", systemImage: "plus") }.help("新建实例 ⌘N").disabled(model.busy)
            }
        }
        .confirmationDialog("将实例移到废纸篓？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { if let target = deleteTarget { model.trash(target) }; deleteTarget = nil }
        } message: { Text(deleteTarget?.repositoryVersionID != nil ? "此版本文件夹及其中的独立存档和模组会移入废纸篓。共享和自定义游戏目录会保留，运行记录仍保存在 Ruri 中。" : (deleteTarget?.runDirectory ?? .isolated) != .isolated ? "此实例的版本清单和运行记录会移入废纸篓。所选运行目录中的存档、模组、备份和游戏设置会保留。" : "实例的存档和模组会一起移入废纸篓。共享游戏文件会保留。") }
        .task(id: model.selectedDirectoryID) { await model.refreshDirectoryAvailability(); await model.refreshMinecraftFolder() }
    }

    private var countLabel: String {
        let total = model.directoryInstances.count
        guard !search.isEmpty else { return "\(total) 个实例" }
        return "\(filtered.count) / \(total) 个实例"
    }

    private var emptyFolder: some View {
        ContentUnavailableView {
            Label("这个文件夹还没有实例", systemImage: "square.grid.2x2")
        } description: {
            Text("新建一个实例，或导入整合包。")
        } actions: {
            Button("新建实例") { model.showCreate = true }.buttonStyle(.borderedProminent)
            Button("导入整合包…") { model.chooseInstanceImport() }
        }
        .disabled(model.busy)
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
            ForEach(filtered) { instance in card(instance) }
            if search.isEmpty {
                DashedTile(symbol: "plus", title: "新建实例", detail: "或从工具栏导入整合包") { model.showCreate = true }
                    .frame(minHeight: 150).disabled(model.busy)
            }
        }
    }

    private func card(_ instance: GameInstance) -> some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    iconButton(instance, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(instance.name).font(.headline).lineLimit(1)
                            if instance.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption2) }
                        }
                        Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    InstanceMenu(instance: instance, onTrash: { deleteTarget = $0 })
                }
                HStack(spacing: 10) {
                    TagPill(text: model.statusLabel(instance), color: model.statusColor(instance))
                    Text(model.memoryLabel(instance)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(instance.lastPlayedLabel).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                if let issue = instance.repositoryIssue { Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(3).help(issue) }
                Divider()
                HStack {
                    InstanceQuickActions(instance: instance)
                    Spacer()
                    LaunchButton(instance: instance)
                }
            }
        }
        .contextMenu { contextActions(instance) }
    }

    // MARK: List

    private var list: some View {
        Surface(padding: 0) {
            VStack(spacing: 0) {
                ForEach(filtered) { instance in
                    row(instance)
                    if instance.id != filtered.last?.id { Divider().padding(.leading, 74) }
                }
            }
        }
    }

    private func row(_ instance: GameInstance) -> some View {
        HStack(spacing: 14) {
            iconButton(instance, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(instance.name).font(.headline).lineLimit(1)
                    if instance.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption2) }
                }
                Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let issue = instance.repositoryIssue { Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(1).help(issue) }
            }
            Spacer(minLength: 12)
            TagPill(text: model.statusLabel(instance), color: model.statusColor(instance))
            Text(model.memoryLabel(instance)).font(.caption).foregroundStyle(.secondary).frame(width: 96, alignment: .trailing).lineLimit(1)
            Text(instance.lastPlayedLabel).font(.caption).foregroundStyle(.tertiary).frame(width: 110, alignment: .trailing).lineLimit(1)
            InstanceQuickActions(instance: instance)
            LaunchButton(instance: instance)
            InstanceMenu(instance: instance, onTrash: { deleteTarget = $0 })
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contextMenu { contextActions(instance) }
    }

    // MARK: Shared pieces

    private func iconButton(_ instance: GameInstance, size: CGFloat) -> some View {
        Button { model.editingInstance = instance } label: {
            InstanceIcon(loader: instance.loader, size: size, png: instance.iconPNG)
        }.buttonStyle(.plain).help("更换图标或编辑实例设置").accessibilityLabel("编辑 \(instance.name) 的图标和设置")
    }

    @ViewBuilder private func contextActions(_ instance: GameInstance) -> some View {
        Button("在主页中显示", systemImage: "house") { model.select(instance) }
        Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
        Button("管理模组与资源包", systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
        Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
        Divider()
        Button("移到废纸篓", systemImage: "trash", role: .destructive) { deleteTarget = instance }.disabled(model.busy || model.isInstanceInUse(instance.id))
    }
}
