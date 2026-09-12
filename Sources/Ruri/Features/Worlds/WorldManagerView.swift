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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) { Image(systemName: "globe.europe.africa.fill").font(.system(size: 38)).foregroundStyle(Theme.accent); SectionHeading(title: Messages.AppWorldManagerView.worldsAndBackups.localized, subtitle: instance.name); Spacer(); Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction) }
            HStack {
                Picker(Messages.AppWorldManagerView.content.localized, selection: $tab) { Text(Messages.AppWorldManagerView.worldCount(Int64(worlds.count)).localized).tag("worlds"); Text(Messages.AppWorldManagerView.backupCount(Int64(backups.count)).localized).tag("backups") }.pickerStyle(.segmented).frame(width: 270)
                Spacer()
                Button(Messages.AppWorldManagerView.importWorld.localized, systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button { model.reveal(instance, folder: "saves") } label: { Image(systemName: "folder") }.help(Messages.AppWorldManagerView.openWorldFolder.localized)
            }
            if model.isInstanceInUse(instance.id) { Label(Messages.AppWorldManagerView.worldEditNotice.localized, systemImage: "play.circle").font(.callout).foregroundStyle(.secondary) }
            if !loading && !quickPlaySupported { Text(Messages.AppWorldManagerView.directWorldLaunchUnsupported.localized).font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let status { Text(status).font(.callout).foregroundStyle(Theme.accent) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if tab == "worlds" {
                            if worlds.isEmpty { EmptyPanel(symbol: "globe", title: Messages.AppWorldManagerView.noWorlds.localized, detail: Messages.AppWorldManagerView.worldDescription.localized) }
                            ForEach(worlds) { world in worldRow(world) }
                        } else {
                            if backups.isEmpty { EmptyPanel(symbol: "clock.arrow.circlepath", title: Messages.AppWorldManagerView.noBackups.localized, detail: Messages.AppWorldManagerView.backupDescription.localized) }
                            ForEach(backups) { backup in backupRow(backup) }
                        }
                    }
                }
            }
            if model.busy {
                Divider()
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Button(Messages.AppWorldManagerView.cancelTask.localized) { model.operation?.cancel() }
                }
            }
        }.padding(24).frame(width: 820, height: 650)
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
        HStack(spacing: 15) {
            Group {
                if let icon = world.icon, let image = NSImage(contentsOf: icon) { Image(nsImage: image).resizable().interpolation(.none).scaledToFill() }
                else { Image(systemName: "mountain.2.fill").resizable().scaledToFit().padding(13).foregroundStyle(Theme.accent) }
            }.frame(width: 58, height: 58).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(world.name).font(.headline).lineLimit(1)
                HStack(spacing: 7) { if let mode = world.gameMode { TagPill(text: mode) }; if let version = world.version { Text(version) }; if let size = world.size { Text(LocalizedFormat.bytes(size)) } }.font(.caption).foregroundStyle(.secondary)
                Text(world.folder).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                if let error = world.metadataError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Button(Messages.AppWorldManagerView.enterWorld.localized, systemImage: "play.fill") { launchingWorld = world; dismiss() }
                .disabled(!canModify || !quickPlaySupported || world.metadataError != nil)
                .help(quickPlaySupported ? Messages.AppWorldManagerView.launchWorldNotice.localized : Messages.AppWorldManagerView.worldLaunchUnsupported.localized)
            Button(Messages.AppWorldManagerView.createBackup.localized, systemImage: "clock.arrow.circlepath") {
                mutate(Messages.AppWorldManagerView.backupWorld(world.name).localized) { id in
                    _ = try await manager.backup(folder: world.folder, progress: progress(id)); status = Messages.AppWorldManagerView.worldBackedUp(world.name).localized
                }
            }.disabled(!canModify)
            Menu {
                Button(Messages.AppWorldManagerView.manageDatapacks.localized) { dataPackWorld = world }.disabled(world.metadataError != nil)
                Button(Messages.AppWorldManagerView.exportZip.localized) { export(world) }.disabled(!canModify)
                Button(Messages.AppWorldManagerView.showInFinder.localized) { NSWorkspace.shared.activateFileViewerSelecting([world.url]) }
                Divider(); Button(Messages.AppWorldManagerView.moveToTrash.localized, role: .destructive) { deletingWorld = world }.disabled(!canModify)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private func backupRow(_ backup: WorldBackup) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "archivebox.fill").font(.system(size: 30)).foregroundStyle(Theme.accent).frame(width: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(backup.title).font(.headline).lineLimit(1)
                Text(LocalizedFormat.date(backup.createdAt, date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                HStack { Text(LocalizedFormat.bytes(backup.size)); Text(backup.metadata?.displayReason ?? Messages.AppWorldManagerView.backupInfoUnavailable.localized) }.font(.caption).foregroundStyle(backup.metadata == nil ? .orange : .secondary)
            }
            Spacer()
            Button(Messages.AppWorldManagerView.restoreAsCopy.localized) { restore(backup, replace: false) }.disabled(!canModify || backup.metadata == nil)
            Menu {
                Button(Messages.AppWorldManagerView.replaceOriginal.localized) { restoreTarget = backup }.disabled(!canModify || backup.metadata == nil)
                Button(Messages.AppWorldManagerView.showInFinder.localized) { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                Divider(); Button(Messages.AppWorldManagerView.moveToTrash.localized, role: .destructive) { deletingBackup = backup }.disabled(!canModify)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
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
