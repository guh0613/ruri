import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct WorldDataPacksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    let world: WorldSnapshot
    @State private var packs: [WorldDataPack] = []
    @State private var error: String?
    @State private var status: String?
    @State private var importing = false
    @State private var searching = false
    @State private var ordering = false
    @State private var loading = false
    @State private var removing: WorldDataPack?
    @State private var backup: URL?
    private var manager: WorldManager { WorldManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !loading && !model.busy && !model.isInstanceInUse(instance.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: Messages.AppWorldDataPacksView.dataPacks.localized, subtitle: world.name)
                Spacer()
                Button(Messages.AppWorldDataPacksView.find.localized, systemImage: "magnifyingglass") { searching = true }.disabled(!canModify)
                Button(Messages.AppWorldDataPacksView.importDataPackAction.localized, systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
            Text(Messages.AppWorldDataPacksView.dataPackAvailability.localized).font(.callout).foregroundStyle(.secondary)
            if model.isInstanceInUse(instance.id) { Label(Messages.AppWorldDataPacksView.exitGameBeforeEditing.localized, systemImage: "play.circle").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let status { Text(status).foregroundStyle(Theme.accent) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if packs.isEmpty { EmptyPanel(symbol: "shippingbox", title: Messages.AppWorldDataPacksView.noLocalDataPacks.localized, detail: Messages.AppWorldDataPacksView.dataPackImportInstructions.localized) }
            else {
                List(packs) { pack in
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(pack.enabled ? Theme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pack.id).font(.headline).lineLimit(1)
                            if !pack.description.isEmpty { Text(pack.description).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            if let format = pack.format { Text(Messages.AppWorldDataPacksView.declaredFormat(String(describing: format)).localized).font(.caption).foregroundStyle(.secondary) }
                            if let error = pack.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                        }
                        Spacer()
                        Toggle(Messages.AppWorldDataPacksView.enable.localized, isOn: Binding(get: { pack.enabled }, set: { value in
                            mutate(value ? Messages.AppWorldDataPacksView.enableDataPack.localized : Messages.AppWorldDataPacksView.disableDataPack.localized) { try await manager.setDataPackEnabled(value, name: pack.id, folder: world.folder) }
                        })).toggleStyle(.switch).labelsHidden().help(pack.enabled ? Messages.AppWorldDataPacksView.disableDataPack.localized : Messages.AppWorldDataPacksView.enableDataPack.localized).disabled(!canModify || pack.error != nil)
                        Menu {
                            Button(Messages.AppWorldDataPacksView.showInFinder.localized) { NSWorkspace.shared.activateFileViewerSelecting([pack.url]) }
                            Button(Messages.AppWorldDataPacksView.moveToTrash.localized, role: .destructive) { removing = pack }.disabled(!canModify)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(.vertical, 7)
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Button(Messages.AppWorldDataPacksView.adjustPriority.localized) { ordering = true }.disabled(!canModify)
                Text(Messages.AppWorldDataPacksView.backupBeforeEditing.localized).font(.caption).foregroundStyle(.secondary)
                if let backup { Button(Messages.AppWorldDataPacksView.showConfigBackup.localized) { NSWorkspace.shared.activateFileViewerSelecting([backup]) }.font(.caption) }
                Spacer()
                Button(Messages.AppWorldDataPacksView.refresh.localized, systemImage: "arrow.clockwise") { error = nil; Task { await reload() } }.disabled(loading || model.busy)
            }
        }.padding(24).frame(width: 760, height: 570)
        .task { await reload() }
        .sheet(isPresented: $searching, onDismiss: { Task { await reload() } }) { WorldDataPackSearchView(instance: instance, world: world) }
        .sheet(isPresented: $ordering, onDismiss: { Task { await reload() } }) { WorldDataPackPriorityView(instance: instance, world: world) }
        .interactiveDismissDisabled(model.busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .zip], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                mutate(Messages.AppWorldDataPacksView.importDataPack.localized) {
                    let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }; defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
                    try await manager.importDataPacks(from: urls, folder: world.folder)
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog(Messages.AppWorldDataPacksView.removeDataPackConfirmation.localized, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(Messages.AppWorldDataPacksView.confirmMoveToTrash.localized, role: .destructive) {
                if let pack = removing { mutate(Messages.AppWorldDataPacksView.removeDataPack.localized) { _ = try await manager.removeDataPack(name: pack.id, folder: world.folder) } }
                removing = nil
            }
        } message: { Text(removing?.id ?? "") }
    }
    private func reload() async {
        loading = true
        do {
            packs = try await manager.dataPacks(folder: world.folder)
            let candidate = try await manager.dataPackBackup(folder: world.folder)
            backup = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func mutate(_ title: String, action: @MainActor @Sendable @escaping () async throws -> Void) {
        guard canModify else { return }; error = nil; status = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { _ in
            do { try await action(); status = Messages.AppWorldDataPacksView.dataPackOperationCompleted(title).localized; await reload() }
            catch { self.error = error.localizedDescription; await reload(); throw error }
        }
    }
}
