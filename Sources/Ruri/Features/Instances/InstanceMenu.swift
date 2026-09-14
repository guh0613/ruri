import RuriLocalization
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
            // Style the items themselves so macOS 27 marks their images visible.
            Group {
                if showsSelect { Button(Messages.AppInstanceMenu.showOnHome.localized, systemImage: "house") { model.select(instance) } }
                Button(instance.favorite ? Messages.AppInstanceMenu.unfavorite.localized : Messages.AppInstanceMenu.favorite.localized, systemImage: instance.favorite ? "star.slash" : "star") { var value = instance; value.favorite.toggle(); model.update(value) }
                Divider()
                Button(Messages.AppInstanceMenu.instanceSettings.localized, systemImage: "slider.horizontal.3") { model.editingInstance = instance }
                Button(Messages.AppInstanceMenu.manageModsAndResourcePacks.localized, systemImage: "puzzlepiece.extension") { model.contentPresentation = .init(instance: instance) }
                Button(Messages.AppInstanceMenu.manageSavesAndBackups.localized, systemImage: "globe") { model.worldInstance = instance }
                Button(Messages.AppInstanceMenu.manageSchematics.localized, systemImage: "square.3.layers.3d") { model.schematicInstance = instance }
                Button(Messages.AppInstanceMenu.showInFinder.localized, systemImage: "folder") { model.reveal(instance) }
                Divider()
                if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                    Button(Messages.AppInstanceMenu.recoverInstanceCopy.localized, systemImage: "arrow.counterclockwise") { model.copyingInstance = instance }.disabled(model.busy)
                } else {
                    Button(Messages.AppInstanceMenu.copyInstance.localized, systemImage: "plus.square.on.square") { model.copyingInstance = instance }.disabled(inUse)
                }
                Button(Messages.AppInstanceMenu.exportInstance.localized, systemImage: "square.and.arrow.up") { model.exportingInstance = instance }.disabled(inUse || !instance.installed)
                if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                    Button(Messages.AppInstanceMenu.recoverInstanceMove.localized, systemImage: "arrow.counterclockwise") { model.movingInstance = instance }.disabled(model.busy)
                } else {
                    Button(Messages.AppInstanceMenu.moveToOtherFolder.localized, systemImage: "arrow.right.square") { model.movingInstance = instance }.disabled(inUse)
                }
                Button(Messages.AppInstanceMenu.repairGameFiles.localized, systemImage: "wrench.and.screwdriver") { model.repair(instance) }.disabled(inUse || !instance.installed)
                if let onTrash {
                    Divider()
                    Button(Messages.AppInstanceMenu.moveToTrash.localized, systemImage: "trash", role: .destructive) { onTrash(instance) }.disabled(inUse)
                }
            }.labelStyle(.titleAndIcon)
        } label: { label }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .labelStyle(.titleAndIcon)
        .help(Messages.AppInstanceMenu.moreActions.localized)
    }
}

extension InstanceMenu where Content == Image {
    /// The ellipsis form used on cards and rows.
    init(instance: GameInstance, showsSelect: Bool = true, onTrash: ((GameInstance) -> Void)? = nil) {
        self.init(instance: instance, showsSelect: showsSelect, onTrash: onTrash) { Image(systemName: "ellipsis.circle") }
    }
}
