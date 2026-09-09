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
    private var manager: WorldManager { WorldManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !model.busy && !model.isInstanceInUse(instance.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) { Image(systemName: "globe.europe.africa.fill").font(.system(size: 38)).foregroundStyle(Theme.accent); SectionHeading(title: "留住每一次冒险", subtitle: instance.name); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            HStack {
                Picker("内容", selection: $tab) { Text("存档 \(worlds.count)").tag("worlds"); Text("备份 \(backups.count)").tag("backups") }.pickerStyle(.segmented).frame(width: 270)
                Spacer()
                Button("导入存档…", systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button { model.reveal(instance, folder: "saves") } label: { Image(systemName: "folder") }.help("打开存档文件夹")
            }
            if model.isInstanceInUse(instance.id) { Label("请先结束游戏，再修改或备份存档。", systemImage: "play.circle").font(.callout).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let status { Text(status).font(.callout).foregroundStyle(Theme.accent) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if tab == "worlds" {
                            if worlds.isEmpty { EmptyPanel(symbol: "globe", title: "世界还在等你创造", detail: "游戏中创建的世界会显示在这里，也可以导入已有存档的文件夹或 ZIP。") }
                            ForEach(worlds) { world in worldRow(world) }
                        } else {
                            if backups.isEmpty { EmptyPanel(symbol: "clock.arrow.circlepath", title: "给冒险留一份备份", detail: "在存档列表中创建备份。恢复时可以保留原世界，或在自动备份后替换原目录。") }
                            ForEach(backups) { backup in backupRow(backup) }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("备份保存在实例内，恢复为副本会保留原存档。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button("取消任务") { model.operation?.cancel() } }
            }
        }.padding(24).frame(width: 820, height: 650)
        .task { await reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .zip]) { result in
            do {
                let url = try result.get()
                mutate("导入存档") { id in
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let folder = try await manager.importWorld(from: url, progress: progress(id))
                    status = "已导入到 \(folder)"; tab = "worlds"
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("替换原存档？", isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }), titleVisibility: .visible) {
            Button("自动备份并恢复", role: .destructive) { if let backup = restoreTarget { restore(backup, replace: true) }; restoreTarget = nil }
        } message: { Text("将恢复到“\(restoreTarget?.metadata?.worldFolder ?? "")”。现有存档会先创建一份自动备份。") }
        .confirmationDialog("移到废纸篓？", isPresented: Binding(get: { deletingWorld != nil || deletingBackup != nil }, set: { if !$0 { deletingWorld = nil; deletingBackup = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) {
                if let world = deletingWorld { mutate("移除存档") { _ in try await manager.removeWorld(folder: world.folder) } }
                if let backup = deletingBackup { mutate("移除备份") { _ in try await manager.removeBackup(backup) } }
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
                HStack(spacing: 7) { if let mode = world.gameMode { TagPill(text: mode) }; if let version = world.version { Text(version) }; if let size = world.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) } }.font(.caption).foregroundStyle(.secondary)
                Text(world.folder).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                if let error = world.metadataError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Button("备份", systemImage: "clock.arrow.circlepath") {
                mutate("备份 \(world.name)") { id in
                    _ = try await manager.backup(folder: world.folder, progress: progress(id)); status = "\(world.name) 已备份"
                }
            }.disabled(!canModify)
            Menu {
                Button("导出 ZIP…") { export(world) }.disabled(!canModify)
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([world.url]) }
                Divider(); Button("移到废纸篓", role: .destructive) { deletingWorld = world }.disabled(!canModify)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private func backupRow(_ backup: WorldBackup) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "archivebox.fill").font(.system(size: 30)).foregroundStyle(Theme.accent).frame(width: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(backup.title).font(.headline).lineLimit(1)
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                HStack { Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file)); Text(backup.metadata?.reason ?? "无法读取备份信息") }.font(.caption).foregroundStyle(backup.metadata == nil ? .orange : .secondary)
            }
            Spacer()
            Button("恢复为副本") { restore(backup, replace: false) }.disabled(!canModify || backup.metadata == nil)
            Menu {
                Button("替换原存档…") { restoreTarget = backup }.disabled(!canModify || backup.metadata == nil)
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                Divider(); Button("移到废纸篓", role: .destructive) { deletingBackup = backup }.disabled(!canModify)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private func reload() async {
        loading = true
        do { worlds = try await manager.worlds(); backups = try await manager.backups() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func progress(_ id: UUID) -> @Sendable (Int, Int) -> Void {
        { done, total in if done % 25 == 0 || done == total { Task { @MainActor in model.progress(id, InstallProgress("处理存档文件", completed: done, total: total)) } } }
    }
    private func mutate(_ title: String, action: @MainActor @Sendable @escaping (UUID) async throws -> Void) {
        guard canModify else { return }; error = nil; status = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { id in
            do { try await action(id); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func restore(_ backup: WorldBackup, replace: Bool) {
        mutate("恢复 \(backup.title)") { id in
            let folder = try await manager.restore(backup, replaceExisting: replace, progress: progress(id)); status = "已恢复到 \(folder)"; tab = "worlds"
        }
    }
    private func export(_ world: WorldSnapshot) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = world.folder + ".zip"
        if panel.runModal() == .OK, let url = panel.url { mutate("导出 \(world.name)") { id in try await manager.exportWorld(folder: world.folder, to: url, progress: progress(id)); status = "已导出存档 ZIP" } }
    }
}
