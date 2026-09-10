import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct InstanceContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var kind = ContentKind.mod
    @State private var files: [LocalContentFile] = []
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    @State private var updates: [String: ContentUpdate] = [:]
    @State private var curseUpdates: [String: CurseForgeUpdate] = [:]
    @State private var cursePlan: CurseForgeContentPlan?
    @State private var updateTask: Task<Void, Never>?
    @State private var updatesChecked = false
    @State private var showImporter = false
    @State private var deleteTarget: LocalContentFile?
    @State private var versionTarget: LocalContentFile?
    private var manager: ContentManager { ContentManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !model.busy && !model.isInstanceInUse(instance.id) }
    private var filtered: [LocalContentFile] { files.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.filename.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                InstanceIcon(loader: instance.loader, png: instance.iconPNG)
                SectionHeading(title: "管理游戏内容", subtitle: instance.name + " · " + instance.subtitle)
                Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker("内容", selection: $kind) { ForEach(ContentKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(width: 270)
                Spacer()
                Button("检查更新", systemImage: "arrow.triangle.2.circlepath") { checkUpdates() }.disabled(updateTask != nil || model.busy || files.allSatisfy { !["modrinth", "curseforge"].contains($0.managed?.provider ?? "") })
                Button("导入…", systemImage: "plus") { showImporter = true }.disabled(!canModify)
                Button { model.reveal(instance, folder: kind.folder) } label: { Image(systemName: "folder") }.help("在 Finder 中打开内容文件夹")
            }
            HStack {
                TextField("搜索已安装内容", text: $search).textFieldStyle(.roundedBorder)
                Text("\(files.filter(\.enabled).count) / \(files.count) 已启用").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if model.isInstanceInUse(instance.id) { Label("游戏运行期间，内容修改暂不可用。", systemImage: "play.circle").font(.callout).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if updateTask != nil { ProgressView("正在检查兼容的正式版本…").controlSize(.small) }
            if updatesChecked && updates.isEmpty && curseUpdates.isEmpty { Label("已是最新兼容正式版", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.accent) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if filtered.isEmpty {
                EmptyPanel(symbol: "puzzlepiece.extension", title: files.isEmpty ? "还没有安装\(kind.title)" : "没有匹配内容", detail: "从本地导入文件，或到“发现内容”安装兼容版本。").frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { file in
                            HStack(alignment: .center, spacing: 14) {
                                Toggle("启用 \(file.title)", isOn: Binding(get: { file.enabled }, set: { enabled in
                                    mutate("\(enabled ? "启用" : "停用") \(file.title)") { try await manager.setEnabled(enabled, file: file) }
                                })).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!canModify)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(file.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); if let provider = file.managed?.provider { TagPill(text: provider == "curseforge" ? "CurseForge" : provider == "modrinth" ? "Modrinth" : provider) } }
                                    HStack(spacing: 8) { if let version = file.version { Text(version).lineLimit(1) }; Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) }.font(.caption).foregroundStyle(.secondary)
                                    Text(file.filename).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).help(file.filename)
                                }
                                Spacer(minLength: 4)
                                if let record = file.managed, let update = updates[record.id] {
                                    Button("更新", systemImage: "arrow.down.circle") { apply(update) }.disabled(!canModify).help("更新至 \(update.available.version_number)")
                                }
                                if let record = file.managed, let update = curseUpdates[record.id] {
                                    Button("更新", systemImage: "arrow.down.circle") { prepare(update) }.disabled(!canModify).help("更新至 \(update.available.displayName)")
                                }
                                Menu {
                                    if let record = file.managed, ["modrinth", "curseforge"].contains(record.provider) {
                                        Button("更换版本…", systemImage: "arrow.triangle.swap") {
                                            updateTask?.cancel(); updatesChecked = false; updates = [:]; curseUpdates = [:]
                                            versionTarget = file
                                        }.disabled(!canModify)
                                    }
                                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                    if let page = file.managed?.modrinthPageURL {
                                        Link("在 Modrinth 查看", destination: page)
                                    }
                                    Divider()
                                    Button("移到废纸篓", role: .destructive) { deleteTarget = file }.disabled(!canModify)
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("停用会保留文件；更新前自动备份，失败可恢复。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button("取消任务") { model.operation?.cancel() } }
                else { Button("发现更多内容", systemImage: "safari") { model.page = .discover; dismiss() } }
            }
        }.padding(24).frame(width: 800, height: 650)
        .task(id: kind) { updateTask?.cancel(); updates.removeAll(); curseUpdates.removeAll(); updatesChecked = false; await reload() }
        .onChange(of: model.busy) { if !model.busy { Task { await reload() } } }
        .sheet(item: $cursePlan) { plan in CurseForgePlanView(plan: plan) }
        .sheet(item: $versionTarget) { file in
            if let record = file.managed { ContentVersionView(record: record, instanceID: instance.id) }
        }
        .onDisappear { updateTask?.cancel() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [kind == .mod ? (UTType(filenameExtension: "jar") ?? .data) : .zip], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                mutate("导入 \(urls.count) 个\(kind.title)") {
                    let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                    defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
                    try await manager.importFiles(urls, kind: kind)
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("将此内容移到废纸篓？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { if let file = deleteTarget { mutate("移除 \(file.title)") { try await manager.remove(file) } }; deleteTarget = nil }
        } message: { Text(deleteTarget?.filename ?? "") }
    }
    private func reload() async {
        loading = true
        do { let items = try await manager.scan(kind); try Task.checkCancellation(); files = items
            let versions = Dictionary(items.compactMap(\.managed).map { ($0.id, $0.versionID) }, uniquingKeysWith: { first, _ in first })
            updates = updates.filter { versions[$0.key] == $0.value.installed.versionID }
            curseUpdates = curseUpdates.filter { versions[$0.key] == $0.value.installed.versionID } }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
    private func mutate(_ title: String, action: @escaping @MainActor @Sendable () async throws -> Void) {
        guard canModify else { return }
        error = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { _ in
            do { try await action(); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func checkUpdates() {
        error = nil; updatesChecked = false
        updateTask = Task {
            defer { updateTask = nil }
            let records = files.compactMap(\.managed)
            var failures: [String] = []
            if records.contains(where: { $0.provider == "modrinth" }) {
                do {
                    let result = try await ModrinthService().updates(for: records, instance: instance)
                    try Task.checkCancellation(); updates = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                } catch { if Task.isCancelled { return }; failures.append("Modrinth：" + error.localizedDescription) }
            }
            if records.contains(where: { $0.provider == "curseforge" }) {
                do {
                    let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).updates(for: records, instance: instance)
                    try Task.checkCancellation(); curseUpdates = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                } catch { if Task.isCancelled { return }; failures.append("CurseForge：" + error.localizedDescription) }
            }
            updatesChecked = failures.isEmpty
            error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }
    private func prepare(_ update: CurseForgeUpdate) {
        error = nil
        model.perform("解析 \(update.installed.title) 更新", presentErrors: false) { _ in
            do {
                let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).plan(file: update.available, instance: instance, paths: model.paths)
                try Task.checkCancellation(); cursePlan = result
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func apply(_ update: ContentUpdate) {
        error = nil
        model.perform("更新 \(update.installed.title)", presentErrors: false, instanceID: instance.id) { id in
            do {
                try await ModrinthService().install(version: update.available, type: update.installed.kind.rawValue, instance: instance, paths: model.paths, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                updates.removeValue(forKey: update.id); await reload()
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
}
