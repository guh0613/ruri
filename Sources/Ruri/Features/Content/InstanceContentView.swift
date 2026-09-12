import RuriLocalization
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
    @State private var statusFilter = ContentStatusFilter.all
    @State private var selection = Set<String>()
    @State private var bulkRemoval: ContentRemovalSelection?
    @State private var loading = false
    @State private var error: String?
    @State private var updates: [String: ContentUpdate] = [:]
    @State private var curseUpdates: [String: CurseForgeUpdate] = [:]
    @State private var cursePlan: CurseForgeContentPlan?
    @State private var batchPlan: ContentBatchUpdatePlan?
    @State private var updateTask: Task<Void, Never>?
    @State private var updatesChecked = false
    @State private var showImporter = false
    @State private var deleteTarget: LocalContentFile?
    @State private var versionTarget: LocalContentFile?
    private var manager: ContentManager { ContentManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !model.busy && !model.isInstanceInUse(instance.id) }
    private var filtered: [LocalContentFile] { files.filter {
        (statusFilter == .all || $0.enabled == (statusFilter == .enabled)) &&
        (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.filename.localizedCaseInsensitiveContains(search))
    } }
    private var selectedFiles: [LocalContentFile] { filtered.filter { selection.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                InstanceIcon(loader: instance.loader, png: instance.iconPNG)
                SectionHeading(title: Messages.AppInstanceContentView.bodyText1.localized, subtitle: instance.name + " · " + instance.subtitle)
                Spacer(); Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker(Messages.AppInstanceContentView.bodyText2.localized, selection: $kind) { ForEach(ContentKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(width: 270).disabled(model.busy)
                Spacer()
                Button(Messages.AppInstanceContentView.bodyText3.localized, systemImage: "arrow.triangle.2.circlepath") { checkUpdates() }.disabled(updateTask != nil || model.busy || files.allSatisfy { !["modrinth", "curseforge"].contains($0.managed?.provider ?? "") })
                if !updates.isEmpty || !curseUpdates.isEmpty {
                    Menu(Messages.AppInstanceContentView.bodyText4.localized) {
                        Button(Messages.AppInstanceContentView.bodyText5.localized) { prepareBatch(selectedFiles) }.disabled(!hasUpdates(selectedFiles))
                        Button(Messages.AppInstanceContentView.bodyText6.localized) { prepareBatch(filtered) }.disabled(!hasUpdates(filtered))
                    }.disabled(!canModify || updateTask != nil)
                }
                Button(Messages.AppInstanceContentView.bodyText7.localized, systemImage: "plus") { showImporter = true }.disabled(!canModify)
                Button { model.reveal(instance, folder: kind.folder) } label: { Image(systemName: "folder") }.help(Messages.AppInstanceContentView.bodyText8.localized)
            }
            HStack {
                TextField(Messages.AppInstanceContentView.bodyText9.localized, text: $search).textFieldStyle(.roundedBorder)
                Picker(Messages.AppInstanceContentView.bodyText10.localized, selection: $statusFilter) { ForEach(ContentStatusFilter.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 110)
                Text(Messages.AppInstanceContentView.bodyText11(String(describing: files.filter(\.enabled).count), Int64(files.count)).localized).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Button(Messages.AppInstanceContentView.bodyText12.localized) { selection = Set(filtered.map(\.id)) }.disabled(filtered.isEmpty || loading)
                if selectedFiles.isEmpty { Text(Messages.AppInstanceContentView.bodyText13.localized).font(.caption).foregroundStyle(.secondary) }
                else {
                    Button(Messages.AppInstanceContentView.bodyText14.localized) { selection.removeAll() }
                    Text(Messages.AppInstanceContentView.bodyText15(Int64(selectedFiles.count)).localized).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(Messages.AppInstanceContentView.bodyText16.localized) { setSelectedEnabled(true) }.disabled(!canModify || selectedFiles.allSatisfy(\.enabled))
                    Button(Messages.AppInstanceContentView.bodyText17.localized) { setSelectedEnabled(false) }.disabled(!canModify || selectedFiles.allSatisfy { !$0.enabled })
                    Button(Messages.AppInstanceContentView.bodyText18.localized, role: .destructive) { bulkRemoval = .init(files: selectedFiles) }.disabled(!canModify)
                }
            }
            if model.isInstanceInUse(instance.id) { Label(Messages.AppInstanceContentView.bodyText19.localized, systemImage: "play.circle").font(.callout).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if updateTask != nil { ProgressView(Messages.AppInstanceContentView.errorText1.localized).controlSize(.small) }
            if updatesChecked && updates.isEmpty && curseUpdates.isEmpty { Label(Messages.AppInstanceContentView.errorText2.localized, systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.accent) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if filtered.isEmpty {
                EmptyPanel(symbol: "puzzlepiece.extension", title: files.isEmpty ? Messages.AppInstanceContentView.errorText3(String(describing: kind.title)).localized : Messages.AppInstanceContentView.errorText4.localized, detail: Messages.AppInstanceContentView.errorText5.localized).frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                        ForEach(filtered) { file in
                            HStack(alignment: .center, spacing: 14) {
                                Toggle(Messages.AppInstanceContentView.errorText6(String(describing: file.title)).localized, isOn: Binding(get: { file.enabled }, set: { enabled in
                                    mutate("\(enabled ? Messages.AppInstanceContentView.errorText7.localized : Messages.AppInstanceContentView.errorText8.localized) \(file.title)") { try await manager.setEnabled(enabled, file: file) }
                                })).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!canModify)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(file.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); if let provider = file.managed?.provider { TagPill(text: provider == "curseforge" ? "CurseForge" : provider == "modrinth" ? "Modrinth" : provider) } }
                                    HStack(spacing: 8) { if let version = file.version { Text(version).lineLimit(1) }; Text(LocalizedFormat.bytes(file.size)) }.font(.caption).foregroundStyle(.secondary)
                                    Text(file.filename).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).help(file.filename)
                                }
                                Spacer(minLength: 4)
                                if let record = file.managed, let update = updates[record.id] {
                                    Button(Messages.AppInstanceContentView.updateText1.localized, systemImage: "arrow.down.circle") { apply(update) }.disabled(!canModify).help(Messages.AppInstanceContentView.updateText2(String(describing: update.available.version_number)).localized)
                                }
                                if let record = file.managed, let update = curseUpdates[record.id] {
                                    Button(Messages.AppInstanceContentView.updateText1.localized, systemImage: "arrow.down.circle") { prepare(update) }.disabled(!canModify).help(Messages.AppInstanceContentView.updateText2(String(describing: update.available.displayName)).localized)
                                }
                                Menu {
                                    if let record = file.managed, ["modrinth", "curseforge"].contains(record.provider) {
                                        Button(Messages.AppInstanceContentView.recordText1.localized, systemImage: "arrow.triangle.swap") {
                                            updateTask?.cancel(); updatesChecked = false; updates = [:]; curseUpdates = [:]
                                            versionTarget = file
                                        }.disabled(!canModify)
                                    }
                                    Button(Messages.AppInstanceContentView.recordText2.localized) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                    if let page = file.managed?.modrinthPageURL {
                                        Link(Messages.AppInstanceContentView.pageText1.localized, destination: page)
                                    }
                                    Divider()
                                    Button(Messages.AppInstanceContentView.pageText2.localized, role: .destructive) { deleteTarget = file }.disabled(!canModify)
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            }.padding(.vertical, 8).tag(file.id)
                        }
                }.listStyle(.bordered)
            }
            Divider()
            HStack {
                Text(Messages.AppInstanceContentView.pageText3.localized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button(Messages.AppInstanceContentView.pageText4.localized) { model.operation?.cancel() } }
                else { Button(Messages.AppInstanceContentView.pageText5.localized, systemImage: "safari") { model.page = .discover; dismiss() } }
            }
        }.padding(24).frame(width: 800, height: 650)
        .task(id: kind) { selection.removeAll(); updateTask?.cancel(); updates.removeAll(); curseUpdates.removeAll(); updatesChecked = false; await reload() }
        .onChange(of: search) { pruneSelection() }
        .onChange(of: statusFilter) { pruneSelection() }
        .onChange(of: model.busy) { if !model.busy { Task { await reload() } } }
        .sheet(item: $cursePlan) { plan in CurseForgePlanView(plan: plan) }
        .sheet(item: $batchPlan) { plan in ContentBatchUpdateView(plan: plan) }
        .sheet(item: $versionTarget) { file in
            if let record = file.managed { ContentVersionView(record: record, instanceID: instance.id) }
        }
        .sheet(item: $bulkRemoval) { selected in
            ContentRemovalView(files: selected.files, instanceID: instance.id) {
                mutate(Messages.AppInstanceContentView.recordText3(Int64(selected.files.count)).localized) {
                    model.noticeFileURL = try await manager.remove(selected.files)
                    model.notice = Messages.AppInstanceContentView.recordText4(Int64(selected.files.count)).localized
                }
            }
        }
        .onDisappear { updateTask?.cancel() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: kind.fileExtensions.map { UTType(filenameExtension: $0) ?? .data }, allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                mutate(Messages.AppInstanceContentView.urlsText1(Int64(urls.count), String(describing: kind.title)).localized) {
                    let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                    defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
                    try await manager.importFiles(urls, kind: kind)
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog(Messages.AppInstanceContentView.scopedText1.localized, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button(Messages.AppInstanceContentView.pageText2.localized, role: .destructive) { if let file = deleteTarget { mutate(Messages.AppInstanceContentView.fileText1(String(describing: file.title)).localized) { try await manager.remove(file) } }; deleteTarget = nil }
        } message: { Text(deleteTarget?.filename ?? "") }
    }
    private func reload() async {
        loading = true
        do { let items = try await manager.scan(kind); try Task.checkCancellation(); files = items; pruneSelection()
            let versions = Dictionary(items.compactMap(\.managed).map { ($0.id, $0.versionID) }, uniquingKeysWith: { first, _ in first })
            updates = updates.filter { versions[$0.key] == $0.value.installed.versionID }
            curseUpdates = curseUpdates.filter { versions[$0.key] == $0.value.installed.versionID } }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
    private func mutate(_ title: String, action: @escaping @MainActor @Sendable () async throws -> Void) {
        guard canModify else { return }
        updateTask?.cancel()
        error = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { _ in
            do { try await action(); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func pruneSelection() { selection.formIntersection(Set(filtered.map(\.id))) }
    private func setSelectedEnabled(_ enabled: Bool) {
        let selected = selectedFiles
        mutate(Messages.AppInstanceContentView.selectedText1(String(describing: enabled ? Messages.AppInstanceContentView.errorText7.localized : Messages.AppInstanceContentView.errorText8.localized), Int64(selected.count)).localized) { try await manager.setEnabled(enabled, files: selected) }
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
        model.perform(Messages.AppInstanceContentView.prepareText1(String(describing: update.installed.title)), presentErrors: false) { _ in
            do {
                let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).plan(file: update.available, instance: instance, paths: model.paths)
                try Task.checkCancellation(); cursePlan = result
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func hasUpdates(_ files: [LocalContentFile]) -> Bool {
        files.contains { file in file.managed.map { updates[$0.id] != nil || curseUpdates[$0.id] != nil } ?? false }
    }
    private func prepareBatch(_ files: [LocalContentFile]) {
        let ids = Set(files.compactMap { $0.managed?.id })
        let selected = updates.values.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
        let curseSelected = curseUpdates.values.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
        error = nil
        model.perform(Messages.AppInstanceContentView.curseSelectedText1, presentErrors: false) { _ in
            do {
                let updater = ContentBatchUpdater(curseforge: CurseForgeService(apiKey: curseSelected.isEmpty ? "" : try CurseForgeKeyStore.load()))
                let result = try await updater.prepare(modrinth: selected, curseforge: curseSelected, instance: instance, paths: model.paths)
                try Task.checkCancellation(); batchPlan = result
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func apply(_ update: ContentUpdate) {
        error = nil
        model.perform(Messages.AppInstanceContentView.applyText1(String(describing: update.installed.title)), presentErrors: false, instanceID: instance.id) { id in
            do {
                try await ModrinthService().install(version: update.available, type: update.installed.kind.rawValue, instance: instance, paths: model.paths, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                updates.removeValue(forKey: update.id); await reload()
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
}
