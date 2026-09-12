import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct WorldManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var worlds: [WorldSnapshot] = []
    @State private var backups: [WorldBackup] = []
    @State private var tab = "worlds"
    @State private var error: String?
    @State private var status: String?
    @State private var loading = false
    @State private var importing = false
    @State private var restoreTarget: WorldBackup?
    @State private var deletingWorld: WorldSnapshot?
    @State private var deletingBackup: WorldBackup?
    @State private var launchingWorld: WorldSnapshot?
    @State private var dataPackWorld: WorldSnapshot?
    @State private var quickPlaySupported = false
    private var manager: WorldManager { WorldManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !model.busy && !model.isInstanceInUse(instance.id) }
    var body: some View {
        InstanceManagementSheet(title: Messages.AppWorldManagerView.worldsAndBackups.localized, instanceName: instance.name) {
            HStack(spacing: 10) {
                Picker(Messages.AppWorldManagerView.content.localized, selection: $tab) {
                    Text(Messages.AppWorldManagerView.worldsTab.localized).tag("worlds")
                    Text(Messages.AppWorldManagerView.backupsTab.localized).tag("backups")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer()
                Button(Messages.AppWorldManagerView.importWorld.localized, systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button(Messages.AppWorldManagerView.openWorldFolder.localized, systemImage: "folder") { model.reveal(instance, folder: "saves") }
                    .labelStyle(.iconOnly).help(Messages.AppWorldManagerView.openWorldFolder.localized)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if model.isInstanceInUse(instance.id) {
                    Label(Messages.AppWorldManagerView.worldEditNotice.localized, systemImage: "play.circle")
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
                if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if tab == "worlds" && worlds.isEmpty {
                    EmptyPanel(symbol: "globe", title: Messages.AppWorldManagerView.noWorlds.localized, detail: Messages.AppWorldManagerView.worldDescription.localized)
                        .frame(maxHeight: .infinity)
                } else if tab == "backups" && backups.isEmpty {
                    EmptyPanel(symbol: "clock.arrow.circlepath", title: Messages.AppWorldManagerView.noBackups.localized, detail: Messages.AppWorldManagerView.backupDescription.localized)
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        if tab == "worlds" { ForEach(worlds) { world in worldRow(world) } }
                        else { ForEach(backups) { backup in backupRow(backup) } }
                    }.listStyle(.inset).scrollContentBackground(.hidden)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Text(tab == "worlds" ? Messages.AppWorldManagerView.worldCount(Int64(worlds.count)).localized : Messages.AppWorldManagerView.backupCount(Int64(backups.count)).localized)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if let status { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(status) }
                Spacer(minLength: 8)
                if model.busy {
                    ProgressView().controlSize(.small)
                    Button(Messages.AppWorldManagerView.cancelTask.localized) { model.operation?.cancel() }
                }
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.borderedProminent)
            }
        }
        .task { await reload() }
        .sheet(item: $dataPackWorld) { world in WorldDataPacksView(instance: instance, world: world) }
        .onDisappear {
            if let world = launchingWorld { launchingWorld = nil; model.launch(instance, world: world) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .zip]) { result in
            do {
                let url = try result.get()
                mutate(Messages.AppWorldManagerView.importWorldTitle.localized) { id in
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let folder = try await manager.importWorld(from: url, progress: progress(id))
                    status = Messages.AppWorldManagerView.worldImported(String(describing: folder)).localized; tab = "worlds"
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog(Messages.AppWorldManagerView.replaceWorldPrompt.localized, isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }), titleVisibility: .visible) {
            Button(Messages.AppWorldManagerView.backupAndRestore.localized, role: .destructive) { if let backup = restoreTarget { restore(backup, replace: true) }; restoreTarget = nil }
        } message: { Text(Messages.AppWorldManagerView.restoreBackupNotice(String(describing: restoreTarget?.metadata?.worldFolder ?? "")).localized) }
        .confirmationDialog(Messages.AppWorldManagerView.trashWorldPrompt.localized, isPresented: Binding(get: { deletingWorld != nil || deletingBackup != nil }, set: { if !$0 { deletingWorld = nil; deletingBackup = nil } }), titleVisibility: .visible) {
            Button(Messages.AppWorldManagerView.moveToTrash.localized, role: .destructive) {
                if let world = deletingWorld { mutate(Messages.AppWorldManagerView.removeWorld.localized) { _ in try await manager.removeWorld(folder: world.folder) } }
                if let backup = deletingBackup { mutate(Messages.AppWorldManagerView.removeBackup.localized) { _ in try await manager.removeBackup(backup) } }
                deletingWorld = nil; deletingBackup = nil
            }
        } message: { Text(deletingWorld?.name ?? deletingBackup?.title ?? "") }
    }
    private func worldRow(_ world: WorldSnapshot) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = world.icon, let image = NSImage(contentsOf: icon) { Image(nsImage: image).resizable().interpolation(.none).scaledToFill() }
                else { Image(systemName: "mountain.2").resizable().scaledToFit().padding(9).foregroundStyle(.secondary) }
            }.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(world.name).font(.body.weight(.medium)).lineLimit(1).help(world.name)
                HStack(spacing: 8) {
                    if let mode = world.gameMode { Text(mode) }
                    if let version = world.version { Text(version) }
                    if let size = world.size { Text(LocalizedFormat.bytes(size)) }
                }.font(.caption).foregroundStyle(.secondary)
                if world.folder != world.name { Text(world.folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(world.folder) }
                if let error = world.metadataError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 12)
            if quickPlaySupported {
                Button(Messages.AppWorldManagerView.enterWorld.localized, systemImage: "play.fill") { launchingWorld = world; dismiss() }
                    .disabled(!canModify || world.metadataError != nil)
            }
            Button(Messages.AppWorldManagerView.createBackup.localized, systemImage: "clock.arrow.circlepath") {
                mutate(Messages.AppWorldManagerView.backupWorld(world.name).localized) { id in
                    _ = try await manager.backup(folder: world.folder, progress: progress(id)); status = Messages.AppWorldManagerView.worldBackedUp(world.name).localized
                }
            }.disabled(!canModify)
            Menu {
                Group {
                    if !quickPlaySupported {
                        Button(Messages.AppWorldManagerView.enterWorld.localized, systemImage: "play.fill") { launchingWorld = world; dismiss() }.disabled(true)
                            .help(Messages.AppWorldManagerView.worldLaunchUnsupported.localized)
                    }
                    Button(Messages.AppWorldManagerView.manageDatapacks.localized, systemImage: "shippingbox") { dataPackWorld = world }.disabled(world.metadataError != nil)
                    Button(Messages.AppWorldManagerView.exportZip.localized, systemImage: "square.and.arrow.up") { export(world) }.disabled(!canModify)
                    Button(Messages.AppWorldManagerView.showInFinder.localized, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([world.url]) }
                    Divider()
                    Button(Messages.AppWorldManagerView.moveToTrash.localized, systemImage: "trash", role: .destructive) { deletingWorld = world }.disabled(!canModify)
                }.labelStyle(.titleAndIcon)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize()
                .help(Messages.AppWorldManagerView.moreActions.localized)
        }.padding(.vertical, 6)
    }

    private func backupRow(_ backup: WorldBackup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox").font(.system(size: 24)).foregroundStyle(.secondary).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.title).font(.body.weight(.medium)).lineLimit(1).help(backup.title)
                HStack(spacing: 8) {
                    Text(LocalizedFormat.date(backup.createdAt, date: .abbreviated, time: .shortened))
                    Text(LocalizedFormat.bytes(backup.size))
                }.font(.caption).foregroundStyle(.secondary)
                Text(backup.metadata?.displayReason ?? Messages.AppWorldManagerView.backupInfoUnavailable.localized)
                    .font(.caption).foregroundStyle(backup.metadata == nil ? .orange : .secondary)
            }
            Spacer(minLength: 12)
            Button(Messages.AppWorldManagerView.restoreAsCopy.localized, systemImage: "arrow.counterclockwise") { restore(backup, replace: false) }.disabled(!canModify || backup.metadata == nil)
            Menu {
                Group {
                    Button(Messages.AppWorldManagerView.replaceOriginal.localized, systemImage: "arrow.triangle.2.circlepath") { restoreTarget = backup }.disabled(!canModify || backup.metadata == nil)
                    Button(Messages.AppWorldManagerView.showInFinder.localized, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                    Divider()
                    Button(Messages.AppWorldManagerView.moveToTrash.localized, systemImage: "trash", role: .destructive) { deletingBackup = backup }.disabled(!canModify)
                }.labelStyle(.titleAndIcon)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize()
                .help(Messages.AppWorldManagerView.moreActions.localized)
        }.padding(.vertical, 6)
    }
    private func reload() async {
        loading = true
        do {
            worlds = try await manager.worlds(); backups = try await manager.backups()
            let current = model.state.instances.first { $0.id == instance.id } ?? instance
            if let manifest = try? await model.installer.loadManifest(current) { quickPlaySupported = WorldQuickPlay.supports(instance: current, manifest: manifest) }
            else { quickPlaySupported = false }
        }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func progress(_ id: UUID) -> @Sendable (Int, Int) -> Void {
        { done, total in if done % 25 == 0 || done == total { Task { @MainActor in model.progress(id, InstallProgress(Messages.AppWorldManagerView.processingWorldFiles, completed: done, total: total)) } } }
    }
    private func mutate(_ title: String, action: @MainActor @Sendable @escaping (UUID) async throws -> Void) {
        guard canModify else { return }; error = nil; status = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { id in
            do { try await action(id); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func restore(_ backup: WorldBackup, replace: Bool) {
        mutate(Messages.AppWorldManagerView.restoreWorld(backup.title).localized) { id in
            let folder = try await manager.restore(backup, replaceExisting: replace, progress: progress(id)); status = Messages.AppWorldManagerView.worldRestored(String(describing: folder)).localized; tab = "worlds"
        }
    }
    private func export(_ world: WorldSnapshot) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = world.folder + ".zip"
        if panel.runModal() == .OK, let url = panel.url { mutate(Messages.AppWorldManagerView.exportWorld(world.name).localized) { id in try await manager.exportWorld(folder: world.folder, to: url, progress: progress(id)); status = Messages.AppWorldManagerView.worldZipExported.localized } }
    }
}
