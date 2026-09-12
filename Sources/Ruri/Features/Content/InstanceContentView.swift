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
        InstanceManagementSheet(title: Messages.AppInstanceContentView.manageGameContent.localized, instanceName: instance.name) {
            controls
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if model.isInstanceInUse(instance.id) {
                    Label(Messages.AppInstanceContentView.contentChangesUnavailableWhileRunning.localized, systemImage: "play.circle")
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
                if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if filtered.isEmpty {
                    EmptyPanel(symbol: "puzzlepiece.extension", title: files.isEmpty ? Messages.AppInstanceContentView.contentNotInstalled(kind.title).localized : Messages.AppInstanceContentView.noMatchingContent.localized, detail: Messages.AppInstanceContentView.importOrDiscoverContent.localized)
                        .frame(maxHeight: .infinity)
                } else { contentTable }
            }
        } footer: {
            footer
        }
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
                mutate(Messages.AppInstanceContentView.removeContentCount(Int64(selected.files.count)).localized) {
                    model.noticeFileURL = try await manager.remove(selected.files)
                    model.notice = Messages.AppInstanceContentView.contentMovedToTrash(Int64(selected.files.count)).localized
                }
            }
        }
        .onDisappear { updateTask?.cancel() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: kind.fileExtensions.map { UTType(filenameExtension: $0) ?? .data }, allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                mutate(Messages.AppInstanceContentView.importContentCount(Int64(urls.count), kind.title).localized) {
                    let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                    defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
                    try await manager.importFiles(urls, kind: kind)
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog(Messages.AppInstanceContentView.moveContentToTrashConfirmation.localized, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button(Messages.AppInstanceContentView.moveToTrash.localized, role: .destructive) { if let file = deleteTarget { mutate(Messages.AppInstanceContentView.removeContent(file.title).localized) { try await manager.remove(file) } }; deleteTarget = nil }
        } message: { Text(deleteTarget?.filename ?? "") }
    }
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Picker(Messages.AppInstanceContentView.content.localized, selection: $kind) {
                    ForEach(ContentKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 250).disabled(model.busy)
                Spacer(minLength: 12)
                Button(Messages.AppInstanceContentView.checkForUpdates.localized, systemImage: "arrow.triangle.2.circlepath", action: checkUpdates)
                    .labelStyle(.iconOnly).help(Messages.AppInstanceContentView.checkForUpdates.localized)
                    .disabled(updateTask != nil || model.busy || files.allSatisfy { !["modrinth", "curseforge"].contains($0.managed?.provider ?? "") })
                if !updates.isEmpty || !curseUpdates.isEmpty {
                    Menu {
                        Button(Messages.AppInstanceContentView.updateSelectedContent.localized, systemImage: "arrow.down.circle") { prepareBatch(selectedFiles) }.disabled(!hasUpdates(selectedFiles))
                        Button(Messages.AppInstanceContentView.updateCurrentResults.localized, systemImage: "arrow.down.circle") { prepareBatch(filtered) }.disabled(!hasUpdates(filtered))
                    } label: {
                        Label(Messages.AppInstanceContentView.batchUpdate.localized, systemImage: "square.and.arrow.down.on.square")
                            .labelStyle(.iconOnly)
                    }.labelStyle(.titleAndIcon).menuIndicator(.hidden).help(Messages.AppInstanceContentView.batchUpdate.localized)
                        .disabled(!canModify || updateTask != nil)
                }
                Button(Messages.AppInstanceContentView.importContent.localized, systemImage: "plus") { showImporter = true }.disabled(!canModify)
                Button(Messages.AppInstanceContentView.discoverMoreContent.localized, systemImage: "safari") { model.page = .discover; dismiss() }
                    .labelStyle(.iconOnly).help(Messages.AppInstanceContentView.discoverMoreContent.localized).disabled(model.busy)
                Button(Messages.AppInstanceContentView.openContentFolder.localized, systemImage: "folder") { model.reveal(instance, folder: kind.folder) }
                    .labelStyle(.iconOnly).help(Messages.AppInstanceContentView.openContentFolder.localized)
            }
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(Messages.AppInstanceContentView.searchInstalledContent.localized, text: $search).textFieldStyle(.plain)
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Picker(Messages.AppInstanceContentView.status.localized, selection: $statusFilter) {
                    ForEach(ContentStatusFilter.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 120)
            }
        }
    }

    private var contentTable: some View {
        Table(filtered, selection: $selection) {
            TableColumn(Messages.AppInstanceContentView.enabledColumn.localized) { file in
                Toggle(Messages.AppInstanceContentView.enableContent(file.title).localized, isOn: Binding(get: { file.enabled }, set: { enabled in
                    mutate("\(enabled ? Messages.AppInstanceContentView.enable.localized : Messages.AppInstanceContentView.disable.localized) \(file.title)") { try await manager.setEnabled(enabled, file: file) }
                })).labelsHidden().toggleStyle(.checkbox).disabled(!canModify)
            }.width(42)
            TableColumn(Messages.AppInstanceContentView.nameColumn.localized) { file in
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.title).font(.body.weight(.medium)).lineLimit(1).help(file.title)
                    Text(file.filename).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(file.filename)
                }.padding(.vertical, 4)
            }.width(min: 190, ideal: 330)
            TableColumn(Messages.AppInstanceContentView.versionColumn.localized) { file in
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.version ?? "—").font(.callout).lineLimit(1).help(file.version ?? "—")
                    if let provider = file.managed?.provider {
                        Text(provider == "curseforge" ? "CurseForge" : provider == "modrinth" ? "Modrinth" : provider)
                            .font(.caption2).lineLimit(1)
                    }
                }.foregroundStyle(.secondary)
            }.width(min: 90, ideal: 130, max: 170)
            TableColumn(Messages.AppInstanceContentView.sizeColumn.localized) { file in
                Text(LocalizedFormat.bytes(file.size)).font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }.width(76)
            TableColumn(Messages.AppInstanceContentView.actionsColumn.localized) { file in
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if let record = file.managed, let update = updates[record.id] {
                        Button(Messages.AppInstanceContentView.update.localized, systemImage: "arrow.down.circle") { apply(update) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(!canModify)
                            .help(Messages.AppInstanceContentView.updateTo(update.available.version_number).localized)
                    }
                    if let record = file.managed, let update = curseUpdates[record.id] {
                        Button(Messages.AppInstanceContentView.update.localized, systemImage: "arrow.down.circle") { prepare(update) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(!canModify)
                            .help(Messages.AppInstanceContentView.updateTo(update.available.displayName).localized)
                    }
                    Menu { fileActions(file) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize()
                        .help(Messages.AppInstanceContentView.actionsColumn.localized)
                }
            }.width(68)
        }.tableStyle(.inset)
    }

    @ViewBuilder private func fileActions(_ file: LocalContentFile) -> some View {
        if let record = file.managed, ["modrinth", "curseforge"].contains(record.provider) {
            Button(Messages.AppInstanceContentView.changeVersion.localized, systemImage: "arrow.triangle.swap") {
                updateTask?.cancel(); updatesChecked = false; updates = [:]; curseUpdates = [:]
                versionTarget = file
            }.disabled(!canModify)
        }
        Button(Messages.AppInstanceContentView.showInFinder.localized, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        if let page = file.managed?.modrinthPageURL {
            Link(destination: page) { Label(Messages.AppInstanceContentView.viewOnModrinth.localized, systemImage: "arrow.up.right.square") }
        }
        Divider()
        Button(Messages.AppInstanceContentView.moveToTrash.localized, systemImage: "trash", role: .destructive) { deleteTarget = file }.disabled(!canModify)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button(Messages.AppInstanceContentView.selectAllCurrentResults.localized, systemImage: "checkmark.square") { selection = Set(filtered.map(\.id)) }
                    .disabled(filtered.isEmpty || loading)
                Button(Messages.AppInstanceContentView.deselect.localized) { selection.removeAll() }.disabled(selectedFiles.isEmpty)
                Divider()
                Button(Messages.AppInstanceContentView.enableSelected.localized, systemImage: "checkmark.circle") { setSelectedEnabled(true) }
                    .disabled(!canModify || selectedFiles.isEmpty || selectedFiles.allSatisfy(\.enabled))
                Button(Messages.AppInstanceContentView.disableSelected.localized, systemImage: "pause.circle") { setSelectedEnabled(false) }
                    .disabled(!canModify || selectedFiles.isEmpty || selectedFiles.allSatisfy { !$0.enabled })
                Button(Messages.AppInstanceContentView.removeSelected.localized, systemImage: "trash", role: .destructive) { bulkRemoval = .init(files: selectedFiles) }
                    .disabled(!canModify || selectedFiles.isEmpty)
            } label: {
                Label(Messages.AppInstanceContentView.selectionActions.localized, systemImage: "checklist").labelStyle(.iconOnly)
            }.menuIndicator(.hidden).labelStyle(.titleAndIcon).help(Messages.AppInstanceContentView.selectionActions.localized)
            Text(selectedFiles.isEmpty
                 ? Messages.AppInstanceContentView.enabledCount(String(files.filter(\.enabled).count), Int64(files.count)).localized
                 : Messages.AppInstanceContentView.selectedCount(Int64(selectedFiles.count)).localized)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: 8)
            if model.busy {
                ProgressView().controlSize(.small)
                Button(Messages.AppInstanceContentView.cancelTask.localized) { model.operation?.cancel() }
            } else if updateTask != nil {
                ProgressView().controlSize(.small)
                Text(Messages.AppInstanceContentView.checkingCompatibleReleases.localized).font(.caption).foregroundStyle(.secondary)
            } else if updatesChecked && updates.isEmpty && curseUpdates.isEmpty {
                Label(Messages.AppInstanceContentView.latestCompatibleRelease.localized, systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.borderedProminent)
        }
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
        mutate(Messages.AppInstanceContentView.selectedContentCount(String(describing: enabled ? Messages.AppInstanceContentView.enable.localized : Messages.AppInstanceContentView.disable.localized), Int64(selected.count)).localized) { try await manager.setEnabled(enabled, files: selected) }
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
        model.perform(Messages.AppInstanceContentView.prepareContentUpdate(update.installed.title), presentErrors: false) { _ in
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
        model.perform(Messages.AppInstanceContentView.prepareBatchUpdate, presentErrors: false) { _ in
            do {
                let updater = ContentBatchUpdater(curseforge: CurseForgeService(apiKey: curseSelected.isEmpty ? "" : try CurseForgeKeyStore.load()))
                let result = try await updater.prepare(modrinth: selected, curseforge: curseSelected, instance: instance, paths: model.paths)
                try Task.checkCancellation(); batchPlan = result
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func apply(_ update: ContentUpdate) {
        error = nil
        model.perform(Messages.AppInstanceContentView.applyContentUpdate(update.installed.title), presentErrors: false, instanceID: instance.id) { id in
            do {
                try await ModrinthService().install(version: update.available, type: update.installed.kind.rawValue, instance: instance, paths: model.paths, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                updates.removeValue(forKey: update.id); await reload()
            } catch { self.error = error.localizedDescription; throw error }
        }
    }
}
