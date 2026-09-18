import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

/// Carry the initial tab with the instance so sheet creation reads one value.
/// Each presentation gets fresh view state, including when reopening an instance.
struct InstanceContentPresentation: Identifiable {
    let id = UUID()
    let instance: GameInstance
    var kind: ContentKind = .mod
}

struct InstanceContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let instance: GameInstance
    @State private var kind: ContentKind
    init(instance: GameInstance, kind: ContentKind = .mod) { self.instance = instance; _kind = State(initialValue: kind) }
    @State private var files: [LocalContentFile] = []
    @State private var filtered: [LocalContentFile] = []
    @State private var filePositions: [String: Int] = [:]
    @State private var enabledCount = 0
    @State private var gameFormat: ResourcePackFormat?
    @State private var metadataTask: Task<Void, Never>?
    @State private var loadGeneration = UUID()
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
    @State private var updateProgress: ContentUpdateCheckProgress?
    @State private var updatesChecked = false
    @State private var checkedFileIDs = Set<String>()
    @State private var showImporter = false
    @State private var dropItemCount: Int?
    @State private var importedFilenames: Set<String>?
    @State private var listLoaded = false
    @State private var deleteTarget: LocalContentFile?
    @State private var versionTarget: LocalContentFile?
    @State private var detailTarget: LocalContentFile?
    @State private var updateGeneration = UUID()
    @State private var identificationNotice: String?
    private var manager: ContentManager { ContentManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !model.busy && !model.readOnly && !model.isInstanceInUse(instance.id) }
    private var selectedFiles: [LocalContentFile] { selection.compactMap { filePositions[$0].map { files[$0] } } }
    private var actionFiles: [LocalContentFile] { selection.isEmpty ? filtered : selectedFiles }
    private var updateCandidates: [LocalContentFile] { actionFiles.filter { !$0.isDirectory } }
    private var selectionSummary: String {
        if !selection.isEmpty { return Messages.AppInstanceContentView.selectedCount(Int64(selection.count)).localized }
        if !search.isEmpty || statusFilter != .all { return Messages.ContentDetails.resultCount(Int64(filtered.count)).localized }
        return Messages.AppInstanceContentView.enabledCount(String(enabledCount), Int64(files.count)).localized
    }
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
                if let identificationNotice {
                    Text(identificationNotice).font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                }
                contentList
            }
        } footer: {
            footer
        }
        .task(id: kind) {
            files = []; filtered = []; filePositions = [:]; enabledCount = 0; gameFormat = nil
            listLoaded = false
            dropItemCount = nil; importedFilenames = nil
            selection.removeAll(); cancelUpdateCheck(); identificationNotice = nil; updates.removeAll(); curseUpdates.removeAll(); updatesChecked = false
            await reload()
            if kind == .resourcepack {
                let format = await ResourcePackGameFormat.shared.read(instance: instance, paths: model.paths)
                if !Task.isCancelled, kind == .resourcepack { gameFormat = format }
            }
        }
        .onChange(of: search) { refilter() }
        .onChange(of: statusFilter) { refilter() }
        .onChange(of: canModify) { if !canModify { dropItemCount = nil } }
        .onChange(of: model.busy) {
            if model.busy { cancelMetadataLoading(); loading = false }
            else { Task { await reload() } }
        }
        .sheet(item: $detailTarget) { file in
            LocalContentDetailView(file: filePositions[file.id].map { files[$0] } ?? file, gameFormat: gameFormat) { source, matches in
                applyIdentities(matches, to: source)
            }
        }
        .sheet(item: $cursePlan) { plan in CurseForgePlanView(plan: plan) }
        .sheet(item: $batchPlan) { plan in ContentBatchUpdateView(plan: plan) }
        .sheet(item: $versionTarget) { file in
            if let record = file.managed { ContentVersionView(record: record, instanceID: instance.id) }
        }
        .sheet(item: $bulkRemoval) { selected in
            ContentRemovalView(files: selected.files, instanceID: instance.id) {
                mutate(Messages.AppInstanceContentView.removeContentCount(Int64(selected.files.count)).localized) {
                    let trashedURL = try await manager.remove(selected.files)
                    model.report(Messages.AppInstanceContentView.contentMovedToTrash(Int64(selected.files.count)), level: .success, fileURL: trashedURL)
                }
            }
        }
        .onDisappear { dropItemCount = nil; cancelUpdateCheck(); cancelMetadataLoading() }
        .interactiveDismissDisabled(model.busy)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: kind.fileExtensions.map { UTType(filenameExtension: $0) ?? .data } + (kind == .mod ? [] : [.folder]), allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                importFiles { urls }
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
                }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal: true, vertical: false).disabled(model.busy)
                Spacer(minLength: 12)
                Button(Messages.AppInstanceContentView.importContent.localized, systemImage: "plus") { showImporter = true }
                    .disabled(!canModify).help(Messages.ContentImport.emptyHint.localized)
                Button(Messages.ContentDetails.download.localized, systemImage: "safari") {
                    model.discovery.switchCollection(type: kind.rawValue)
                    model.discovery.change { query in
                        query.text = ""; query.category = ""; query.game = instance.gameVersion
                        query.loader = kind == .mod ? instance.loader.modrinthLoader : ""
                    }
                    model.discovery.preferredInstanceID = instance.id
                    model.discovery.path = []
                    model.page = .discover; dismiss()
                }
                    .labelStyle(.titleAndIcon).help(Messages.AppInstanceContentView.discoverMoreContent.localized).disabled(model.busy)
                Button(Messages.AppInstanceContentView.showInFinder.localized, systemImage: "folder") { model.reveal(instance, folder: kind.folder) }
                    .labelStyle(.titleAndIcon).help(Messages.AppInstanceContentView.openContentFolder.localized)
            }
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(Messages.AppInstanceContentView.searchInstalledContent.localized, text: $search).textFieldStyle(.plain)
                    if metadataTask != nil {
                        ProgressView().controlSize(.small)
                            .help(Messages.ContentDetails.loadingMetadata.localized)
                            .accessibilityLabel(Messages.ContentDetails.loadingMetadata.localized)
                    }
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Picker(Messages.AppInstanceContentView.status.localized, selection: $statusFilter) {
                    ForEach(ContentStatusFilter.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 112)
                Button(Messages.ContentDetails.refresh.localized, systemImage: "arrow.clockwise") { Task { await reload() } }
                    .labelStyle(.iconOnly).help(Messages.ContentDetails.refresh.localized)
                    .disabled(loading || model.busy || updateTask != nil)
            }
        }
    }

    private var importFormats: String {
        switch kind {
        case .mod: Messages.ContentImport.modFormats.localized
        case .resourcepack: Messages.ContentImport.resourcePackFormats.localized
        case .shader: Messages.ContentImport.shaderFormats.localized
        }
    }
    private var importUnavailable: Bool { model.readOnly || model.isInstanceInUse(instance.id) }
    private var contentList: some View {
        Group {
            if loading || (filtered.isEmpty && metadataTask != nil) { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if filtered.isEmpty {
                EmptyPanel(symbol: "square.and.arrow.down", title: files.isEmpty ? Messages.AppInstanceContentView.contentNotInstalled(kind.title).localized : Messages.AppInstanceContentView.noMatchingContent.localized,
                           detail: importUnavailable ? Messages.ContentImport.unavailable.localized : Messages.ContentImport.emptyHint.localized)
                    .frame(maxHeight: .infinity)
            } else { contentTable }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], delegate: ContentImportDropDelegate(isEnabled: canModify, itemCount: $dropItemCount) { providers in
            importFiles { try await ContentImportDropDelegate.fileURLs(from: providers) }
        })
        .overlay {
            if let count = dropItemCount, canModify {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08))
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                        Text(Messages.ContentImport.dropTitle(Int64(count), kind.title).localized).font(.headline)
                        Text(importFormats).font(.callout).foregroundStyle(.secondary)
                        Text(Messages.ContentImport.copyHint.localized).font(.caption).foregroundStyle(.secondary)
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }.padding(6).allowsHitTesting(false)
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
                HStack(spacing: 10) {
                    LocalContentIcon(file: file)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.displayTitle).font(.body.weight(.medium)).lineLimit(1).help(file.displayTitle)
                        Text(file.filename).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(file.filename)
                        if file.kind != .mod, let summary = file.summary {
                            Text(summary.replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(summary)
                        }
                    }
                }.padding(.vertical, 5)
            }.width(min: 190, ideal: 330)
            TableColumn(Messages.AppInstanceContentView.versionColumn.localized) { file in
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.version ?? "—").font(.callout).lineLimit(1).help(file.version ?? "—")
                    if let provider = file.managed?.provider {
                        Text(provider == "curseforge" ? "CurseForge" : provider == "modrinth" ? "Modrinth" : Messages.ContentDetails.localFile.localized)
                            .font(.caption2).lineLimit(1)
                    }
                    if file.kind == .resourcepack {
                        let compatibility = file.compatibility(with: gameFormat)
                        if compatibility.isWarning {
                            Label(compatibility.title, systemImage: "exclamationmark.triangle")
                                .font(.caption2).foregroundStyle(.orange).lineLimit(1).help(compatibility.title)
                        }
                    } else if file.kind == .shader, let state = file.packMetadata?.state, state != .valid {
                        Label(Messages.ContentDetails.missingShaders.localized, systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange).lineLimit(1).help(Messages.ContentDetails.missingShaders.localized)
                    }
                }.foregroundStyle(.secondary)
            }.width(min: 90, ideal: 130, max: 170)
            TableColumn(Messages.AppInstanceContentView.sizeColumn.localized) { file in
                Text(file.isDirectory ? Messages.ContentDetails.folder.localized : LocalizedFormat.bytes(file.size)).font(.callout).foregroundStyle(.secondary)
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
                    Button(Messages.ContentDetails.details.localized, systemImage: "info.circle") { detailTarget = file }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help(Messages.ContentDetails.details.localized)
                    Menu { fileActions(file).labelStyle(.titleAndIcon) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize()
                        .help(Messages.AppInstanceContentView.actionsColumn.localized)
                }
            }.width(76)
        }.tableStyle(.inset)
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let file = files.first(where: { ids.contains($0.id) }) { fileActions(file); Divider() }
                Button(Messages.AppInstanceContentView.selectAllCurrentResults.localized, systemImage: "checkmark.square") { selection = Set(filtered.map(\.id)) }
                    .disabled(filtered.isEmpty || loading)
            } primaryAction: { ids in
                if ids.count == 1 { detailTarget = files.first(where: { ids.contains($0.id) }) }
            }
    }

    @ViewBuilder private func fileActions(_ file: LocalContentFile) -> some View {
        Button(Messages.ContentDetails.details.localized, systemImage: "info.circle") { detailTarget = file }
        if let record = file.managed, ["modrinth", "curseforge"].contains(record.provider) {
            Button(Messages.AppInstanceContentView.changeVersion.localized, systemImage: "arrow.triangle.swap") {
                cancelUpdateCheck(); updatesChecked = false; updates = [:]; curseUpdates = [:]
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
            HStack(spacing: 6) {
                Text(selectionSummary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1).help(selectionSummary)
                if !selection.isEmpty {
                    Button(Messages.AppInstanceContentView.deselect.localized, systemImage: "xmark.circle.fill") { selection.removeAll() }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(Messages.AppInstanceContentView.deselect.localized)
                }
            }.frame(width: 96, alignment: .leading)
            Divider().frame(height: 18)
            HStack(spacing: 8) {
                updateActions
                if !selection.isEmpty {
                    Divider().frame(height: 18)
                    Button(Messages.AppInstanceContentView.enable.localized, systemImage: "checkmark.circle") { setSelectedEnabled(true) }
                        .disabled(!canModify || loading || selectedFiles.allSatisfy(\.enabled))
                    Button(Messages.AppInstanceContentView.disable.localized, systemImage: "pause.circle") { setSelectedEnabled(false) }
                        .disabled(!canModify || loading || selectedFiles.allSatisfy { !$0.enabled })
                    Button(Messages.AppInstanceContentView.moveToTrash.localized, systemImage: "trash", role: .destructive) { bulkRemoval = .init(files: selectedFiles) }
                        .disabled(!canModify || loading)
                }
            }.labelStyle(.titleAndIcon).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 24)
            Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent).controlSize(.regular).disabled(model.busy)
        }.controlSize(.small).frame(minHeight: 28)
    }

    private var updateActions: some View {
        HStack(spacing: 8) {
            if model.busy {
                ProgressView().controlSize(.small)
                Button(Messages.AppInstanceContentView.cancelTask.localized) { model.operation?.cancel() }
            } else if updateTask != nil {
                ProgressView().controlSize(.small).help(Messages.ContentDetails.identifyingUpdates.localized)
                if let updateProgress, updateProgress.total > 0 {
                    Text("\(updateProgress.completed)/\(updateProgress.total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 60, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel(Messages.ContentDetails.updateProgress(Int64(updateProgress.completed), Int64(updateProgress.total)).localized)
                }
                Button(Messages.Common.cancel.localized) { cancelUpdateCheck() }
            } else {
                Button(Messages.AppInstanceContentView.checkForUpdates.localized, systemImage: "arrow.triangle.2.circlepath") { checkUpdates() }
                    .disabled(updateCandidates.isEmpty || loading)
                    .help(updateCandidates.isEmpty && !actionFiles.isEmpty ? Messages.ContentDetails.folderOnlineInfo.localized : Messages.AppInstanceContentView.checkForUpdates.localized)
                if hasUpdates(updateCandidates) {
                    Button(Messages.AppInstanceContentView.update.localized, systemImage: "arrow.down.circle") { prepareBatch(updateCandidates) }
                        .disabled(!canModify || loading)
                } else if updatesChecked && checkedFileIDs == Set(updateCandidates.map(\.id)) {
                    Label(Messages.ContentDetails.noIdentifiedUpdates.localized, systemImage: "checkmark.circle")
                        .labelStyle(.iconOnly).foregroundStyle(.secondary).help(Messages.ContentDetails.noIdentifiedUpdates.localized)
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: model.busy)
        .animation(reduceMotion ? nil : .default, value: updateTask != nil)
    }

    private func reload() async {
        cancelMetadataLoading()
        let generation = loadGeneration, requestedKind = kind
        loading = !listLoaded
        defer { if loadGeneration == generation { loading = false } }
        do {
            let items = try await manager.scan(requestedKind, cachedOnly: true)
            try Task.checkCancellation()
            guard loadGeneration == generation, kind == requestedKind else { return }
            listLoaded = true
            files = items
            filePositions = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
            enabledCount = items.lazy.filter(\.enabled).count
            if let importedFilenames {
                selection = Set(items.filter { importedFilenames.contains($0.filename) }.map(\.id))
                self.importedFilenames = nil
            }
            refilter()
            let versions = Dictionary(items.compactMap(\.managed).map { ($0.id, $0.versionID) }, uniquingKeysWith: { first, _ in first })
            updates = updates.filter { versions[$0.key] == $0.value.installed.versionID }
            curseUpdates = curseUpdates.filter { versions[$0.key] == $0.value.installed.versionID }
            guard items.contains(where: { !$0.metadataLoaded }) else { return }
            let cacheDirectory = model.paths.cache
            metadataTask = Task {
                await ContentMetadataLoader.enrich(items, cacheDirectory: cacheDirectory) { batch in
                    await MainActor.run {
                        guard loadGeneration == generation else { return }
                        // Preserve the snapshot's ordering while names and icons arrive.
                        for file in batch {
                            if let position = filePositions[file.id] {
                                let current = files[position].identities
                                files[position] = current.isEmpty ? file : file.presenting(identities: current)
                            }
                        }
                        refilter()
                    }
                }
                if loadGeneration == generation { metadataTask = nil }
            }
        } catch { if !Task.isCancelled, loadGeneration == generation { self.error = error.localizedDescription } }
    }
    private func cancelMetadataLoading() {
        loadGeneration = UUID(); metadataTask?.cancel(); metadataTask = nil
    }
    private func refilter() {
        let key = LocalContentFile.searchKey(search)
        filtered = files.filter {
            (statusFilter == .all || $0.enabled == (statusFilter == .enabled)) && $0.matches(searchKey: key)
        }
        selection.formIntersection(Set(filtered.map(\.id)))
    }
    private func applyIdentities(_ identities: [ContentIdentity], to source: LocalContentFile) {
        guard let position = filePositions[source.id], files[position].contentRevision == source.contentRevision else { return }
        files[position] = files[position].presenting(identities: identities)
        refilter()
    }
    private func mutate(_ title: String, action: @escaping @MainActor @Sendable () async throws -> Void) {
        guard canModify else { return }
        cancelUpdateCheck()
        error = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { _ in
            // Fast operations can start and finish between SwiftUI updates.
            do { try await action(); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func importFiles(_ loadURLs: @escaping @MainActor @Sendable () async throws -> [URL]) {
        let destinationKind = kind
        mutate(Messages.ContentImport.importing(destinationKind.title).localized) {
            let input = try await loadURLs()
            try Task.checkCancellation()
            guard !input.isEmpty, input.allSatisfy(\.isFileURL) else { throw RuriError.message(Messages.ContentImport.invalidDrop) }
            var seen = Set<URL>()
            let urls = input.filter { seen.insert($0.standardizedFileURL).inserted }
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
            try await manager.importFiles(urls, kind: destinationKind)
            guard kind == destinationKind else { return }
            search = ""; statusFilter = .all
            importedFilenames = Set(urls.map(\.lastPathComponent))
        }
    }
    private func setSelectedEnabled(_ enabled: Bool) {
        let selected = selectedFiles
        mutate(Messages.AppInstanceContentView.selectedContentCount(String(describing: enabled ? Messages.AppInstanceContentView.enable.localized : Messages.AppInstanceContentView.disable.localized), Int64(selected.count)).localized) { try await manager.setEnabled(enabled, files: selected) }
    }
    private func checkUpdates() {
        let snapshot = updateCandidates
        guard updateTask == nil, !snapshot.isEmpty else { return }
        error = nil; identificationNotice = nil; updatesChecked = false; updates = [:]; curseUpdates = [:]; updateProgress = nil
        let generation = UUID(); updateGeneration = generation
        updateTask = Task {
            defer { if updateGeneration == generation { updateTask = nil; updateProgress = nil } }
            var failures: [String] = []
            let key = try? CurseForgeKeyStore.load()
            let curseforge = key.map { CurseForgeService(apiKey: $0) }
            do {
                let service = ContentIdentificationService(cacheDirectory: model.paths.cache, curseforge: curseforge)
                let unknown = snapshot.filter { $0.managed == nil || $0.managed?.provider == "local" }
                if !unknown.isEmpty {
                    let result = try await service.identify(unknown)
                    try Task.checkCancellation()
                    for file in unknown {
                        if let matches = result.matches[file.id] { applyIdentities(matches, to: file) }
                    }
                    failures += result.failures
                    let skipped = try await manager.associate(unknown, matches: result.matches)
                    if !skipped.isEmpty { failures.append(Messages.ContentDetails.duplicateProjects(skipped.joined(separator: ", ")).localized) }
                    await reload()
                }
                try Task.checkCancellation()
            } catch { if Task.isCancelled { return }; failures.append(error.localizedDescription) }
            let scopeIDs = Set(snapshot.map(\.id))
            let scopedFiles = files.filter { scopeIDs.contains($0.id) }
            let records = scopedFiles.compactMap(\.managed)
            do {
                let result = try await ContentUpdateChecker(curseforge: curseforge).check(records, instance: instance) { progress in
                    await MainActor.run {
                        guard updateGeneration == generation else { return }
                        updateProgress = progress
                    }
                }
                try Task.checkCancellation()
                guard updateGeneration == generation else { return }
                updates = Dictionary(result.modrinth.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                curseUpdates = Dictionary(result.curseforge.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                if let failure = result.failureDescription { failures.append(failure) }
            } catch { if Task.isCancelled { return }; failures.append(error.localizedDescription) }
            guard !Task.isCancelled, updateGeneration == generation else { return }
            let unmatched = scopedFiles.filter { !["modrinth", "curseforge"].contains($0.managed?.provider ?? "") }.count
            identificationNotice = unmatched > 0 ? Messages.ContentDetails.unmatchedCount(Int64(unmatched)).localized : nil
            checkedFileIDs = scopeIDs
            updatesChecked = failures.isEmpty
            error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }
    private func cancelUpdateCheck() {
        updateTask?.cancel(); updateTask = nil; updateProgress = nil; updateGeneration = UUID()
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
