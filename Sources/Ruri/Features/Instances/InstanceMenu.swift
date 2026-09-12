import SwiftUI
import RuriCore

/// The full set of instance actions, shared by the library cards and rows
/// and the home page so every entry point offers the same commands.
struct InstanceMenu<Content: View>: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    /// Hidden on the home page, where the instance is already the one shown.
    var showsSelect = true
    /// When nil the destructive entry is omitted, so callers without a
    /// confirmation dialog never expose it.
    var onTrash: ((GameInstance) -> Void)? = nil
    @ViewBuilder var label: Content
    private var inUse: Bool { model.busy || model.isInstanceInUse(instance.id) }
    var body: some View {
        Menu {
            if showsSelect { Button("在主页中显示", systemImage: "house") { model.select(instance) } }
            Button(instance.favorite ? "取消收藏" : "收藏", systemImage: instance.favorite ? "star.slash" : "star") { var value = instance; value.favorite.toggle(); model.update(value) }
            Divider()
            Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
            Button("管理模组与资源包", systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
            Button("管理存档与备份", systemImage: "globe") { model.worldInstance = instance }
            Button("管理原理图", systemImage: "square.3.layers.3d") { model.schematicInstance = instance }
            Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
            Divider()
            if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                Button("恢复实例复制…", systemImage: "arrow.counterclockwise") { model.copyingInstance = instance }.disabled(model.busy)
            } else {
                Button("复制实例…", systemImage: "plus.square.on.square") { model.copyingInstance = instance }.disabled(inUse)
            }
            Button("导出实例…", systemImage: "square.and.arrow.up") { model.exportingInstance = instance }.disabled(inUse || !instance.installed)
            if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                Button("恢复实例移动…", systemImage: "arrow.counterclockwise") { model.movingInstance = instance }.disabled(model.busy)
            } else {
                Button("移动到其他文件夹…", systemImage: "folder.badge.arrow.forward") { model.movingInstance = instance }.disabled(inUse)
            }
            Button("修复游戏文件", systemImage: "wrench.and.screwdriver") { model.repair(instance) }.disabled(inUse || !instance.installed)
            if let onTrash {
                Divider()
                Button("移到废纸篓", systemImage: "trash", role: .destructive) { onTrash(instance) }.disabled(inUse)
            }
        } label: { label }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("更多操作")
    }
}

extension InstanceMenu where Content == Image {
    /// The ellipsis form used on cards and rows.
    init(instance: GameInstance, showsSelect: Bool = true, onTrash: ((GameInstance) -> Void)? = nil) {
        self.init(instance: instance, showsSelect: showsSelect, onTrash: onTrash) { Image(systemName: "ellipsis.circle") }
    }
}
