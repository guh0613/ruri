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
    @State private var loading = false
    @State private var removing: WorldDataPack?
    @State private var backup: URL?
    private var manager: WorldManager { WorldManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !loading && !model.busy && !model.isInstanceInUse(instance.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "数据包", subtitle: world.name)
                Spacer()
                Button("导入…", systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
            Text("适用于 Minecraft 1.13 及以后版本，下次进入世界时生效。移除涉及世界生成的数据包前，建议先备份存档。").font(.callout).foregroundStyle(.secondary)
            if model.isInstanceInUse(instance.id) { Label("请退出游戏后再修改数据包。", systemImage: "play.circle").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let status { Text(status).foregroundStyle(Theme.accent) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if packs.isEmpty { EmptyPanel(symbol: "shippingbox", title: "这个世界还没有本地数据包", detail: "导入根目录包含 pack.mcmeta 的 ZIP 或文件夹。游戏与模组自带的数据包不在此列表中。") }
            else {
                List(packs) { pack in
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(pack.enabled ? Theme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pack.id).font(.headline).lineLimit(1)
                            if !pack.description.isEmpty { Text(pack.description).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            if let format = pack.format { Text("声明格式：\(format)").font(.caption).foregroundStyle(.secondary) }
                            if let error = pack.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                        }
                        Spacer()
                        Toggle("启用", isOn: Binding(get: { pack.enabled }, set: { value in
                            mutate(value ? "启用数据包" : "停用数据包") { try await manager.setDataPackEnabled(value, name: pack.id, folder: world.folder) }
                        })).toggleStyle(.switch).labelsHidden().help(pack.enabled ? "停用数据包" : "启用数据包").disabled(!canModify || pack.error != nil)
                        Menu {
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([pack.url]) }
                            Button("移到废纸篓…", role: .destructive) { removing = pack }.disabled(!canModify)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(.vertical, 7)
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Text("修改前会保留上一份世界配置备份。").font(.caption).foregroundStyle(.secondary)
                if let backup { Button("显示配置备份") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }.font(.caption) }
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { error = nil; Task { await reload() } }.disabled(loading || model.busy)
            }
        }.padding(24).frame(width: 760, height: 570)
        .task { await reload() }
        .interactiveDismissDisabled(model.busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .zip]) { result in
            do {
                let url = try result.get()
                mutate("导入数据包") {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try await manager.importDataPack(from: url, folder: world.folder)
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("移除数据包？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) {
                if let pack = removing { mutate("移除数据包") { _ = try await manager.removeDataPack(name: pack.id, folder: world.folder) } }
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
            do { try await action(); status = "\(title)完成，下次进入世界时生效。"; await reload() }
            catch { self.error = error.localizedDescription; await reload(); throw error }
        }
    }
}
