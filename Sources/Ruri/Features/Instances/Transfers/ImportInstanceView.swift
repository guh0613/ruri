import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ImportInstanceView: View {
    @Environment(AppModel.self) private var model
    let prepared: PreparedInstanceImport
    let updateTarget: GameInstance?
    let onPreparedUpdate: (@MainActor @Sendable (PreparedModpackUpdate) -> Void)?
    let onCancel: (@MainActor @Sendable () -> Void)?
    @State private var name: String
    @State private var keepJVMArguments = false
    @State private var files: [PlannedCurseFile]?
    @State private var excluded = Set<Int>()
    @State private var excludedOptional = Set<String>()
    /// Settings the pack sets that the player chose to leave to the global defaults.
    @State private var inheritedSettings = Set<LaunchSettingKey>()
    private var selectedImport: PreparedInstanceImport { prepared.selectingOptionalFiles(excluding: excludedOptional).inheritingLaunchSettings(inheritedSettings) }
    @State private var manualFiles: [Int: URL] = [:]
    @State private var resolving = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var browsing: ImportContentGroup?
    /// The form's content height, so the sheet grows with its settings and
    /// only scrolls past a limit. macOS 14 keeps a fixed height.
    @State private var settingsHeight: CGFloat = 300
    private var chosenFiles: [PlannedCurseFile] { files?.filter { !excluded.contains($0.id) } ?? [] }
    private var ready: Bool { prepared.curseForgeFiles.isEmpty || files != nil && chosenFiles.filter(\.requiresManualDownload).allSatisfy { manualFiles[$0.id] != nil } }
    private var optionalCurseFiles: [PlannedCurseFile] {
        let ids = Set(prepared.curseForgeFiles.filter { $0.required == false }.map(\.fileID))
        return files?.filter { ids.contains($0.id) } ?? []
    }
    init(prepared: PreparedInstanceImport, updateTarget: GameInstance? = nil, onPreparedUpdate: (@MainActor @Sendable (PreparedModpackUpdate) -> Void)? = nil, onCancel: (@MainActor @Sendable () -> Void)? = nil) {
        self.prepared = prepared; self.updateTarget = updateTarget; self.onPreparedUpdate = onPreparedUpdate; self.onCancel = onCancel
        _name = State(initialValue: prepared.instance.name); _keepJVMArguments = State(initialValue: prepared.format == "MCBBS" || prepared.includesInstallation); _excludedOptional = State(initialValue: prepared.omittedOptionalPaths)
    }
    /// Everything the import places in the instance's content folders, and
    /// the pack's other downloads, as the player has chosen them so far.
    private var contents: [ImportContentEntry] {
        let bundled = prepared.bundledContent.map { ImportContentEntry(path: $0.path, size: $0.size, source: .bundled) }
        let downloads = prepared.remoteFiles.filter { !excludedOptional.contains($0.path) }.map { ImportContentEntry(path: $0.path, size: $0.size, source: .download) }
        let curse = chosenFiles.map { ImportContentEntry(id: "curseforge:\($0.id)", name: $0.project.name, detail: $0.file.fileName, kind: $0.kind, size: $0.file.fileLength, source: $0.requiresManualDownload ? .manual : .download) }
        return bundled + downloads + curse
    }
    var body: some View {
        let contents = contents
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 18)
            FactStrip(items: facts(contents)).padding(.horizontal, 24)
                .popover(item: $browsing, arrowEdge: .bottom) { ImportContentBrowser(contents: contents, group: $0) }
            settingsForm
            Divider()
            HStack {
                Button(Messages.Common.cancel.localized) { task?.cancel(); if let onCancel { onCancel() } else { model.cancelImport(prepared) } }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Spacer()
                Button(updateTarget == nil ? Messages.AppImportInstanceView.importInstance.localized : Messages.AppImportInstanceView.viewUpdateDiff.localized) {
                    if let updateTarget, let onPreparedUpdate {
                        model.prepareModpackUpdate(selectedImport, instance: updateTarget, keepJVMArguments: keepJVMArguments, curseFiles: chosenFiles, manualFiles: manualFiles, completion: onPreparedUpdate)
                    } else { model.finishImport(selectedImport, name: name, keepJVMArguments: keepJVMArguments, curseFiles: chosenFiles, manualFiles: manualFiles) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || resolving || !ready || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 600).interactiveDismissDisabled()
        .onAppear { if model.curseForgeConfigured && !prepared.curseForgeFiles.isEmpty { resolve() } }
        .onDisappear { task?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            InstanceIcon(prepared.instance, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(updateTarget == nil ? Messages.AppImportInstanceView.importGameInstance.localized : Messages.AppImportInstanceView.prepareModpackUpdate.localized)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(prepared.instance.name).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                InstanceMetadata(instance: prepared.instance, compact: true)
                HStack(spacing: 14) {
                    Label(prepared.includesInstallation ? Messages.CoreInstanceTransfer.ruriFullCopy.localized : prepared.format, systemImage: "shippingbox")
                    if let version = prepared.packVersion { Label(version, systemImage: "tag") }
                    if let author = prepared.author { Label(author, systemImage: "person") }
                }.font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let summary = prepared.summary { Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(3).help(summary) }
            }
            Spacer(minLength: 0)
        }
    }

    /// Kind counts open the full list; download and archive totals stay as facts.
    private func facts(_ contents: [ImportContentEntry]) -> [FactStripItem] {
        var items: [FactStripItem] = ContentKind.allCases.compactMap { kind in
            let count = contents.filter { $0.kind == kind }.count
            guard count > 0 else { return nil }
            return FactStripItem(id: kind.rawValue, label: kind.title, value: count.formatted(), detail: Messages.AppImportInstanceView.browseContent.localized) { browsing = .kind(kind) }
        }
        if files == nil && !prepared.curseForgeFiles.isEmpty {
            items.append(FactStripItem(id: "curseforge", label: Messages.AppImportInstanceView.curseForgeFiles.localized, value: prepared.curseForgeFiles.count.formatted(),
                                       detail: Messages.AppImportInstanceView.awaitingResolution.localized))
        }
        let downloads = contents.filter { $0.source != .bundled }
        if !downloads.isEmpty {
            items.append(FactStripItem(id: "downloads", label: Messages.AppImportInstanceView.pendingDownloads.localized, value: downloads.count.formatted(),
                                       detail: LocalizedFormat.bytes(downloads.reduce(0) { $0 + ($1.size ?? 0) })))
        }
        items.append(FactStripItem(id: "files", label: Messages.AppImportInstanceView.migratedContent.localized, value: prepared.fileCount.formatted(), detail: LocalizedFormat.bytes(prepared.byteCount)))
        return items
    }

    private var settingsForm: some View {
        let form = Form {
            Section {
                if let updateTarget {
                    LabeledContent(Messages.AppImportInstanceView.updatingInstance.localized, value: updateTarget.name)
                } else {
                    HStack(spacing: 20) {
                        Text(Messages.AppImportInstanceView.instanceName.localized).fixedSize()
                        TextField(Messages.AppImportInstanceView.instanceName.localized, text: $name)
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    LabeledContent(Messages.AppImportInstanceView.saveTo.localized) { Label(model.selectedDirectoryName, systemImage: "folder") }
                }
                launchSettings
                if let java = prepared.instance.supportedJavaMajors, !java.isEmpty {
                    LabeledContent(Messages.AppImportInstanceView.supportedJava.localized, value: LocalizedFormat.list(java.map(String.init)))
                }
            } footer: {
                if !prepared.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(prepared.warnings, id: \.self) { Label($0, systemImage: "info.circle") }
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            curseForgeStatus
            manualDownloads
            optionalContent
            arguments
        }.formStyle(.grouped).scrollContentBackground(.hidden)
        return Group {
            if #available(macOS 15, *) {
                form.onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom } action: { _, height in settingsHeight = height }
                    .frame(height: min(max(settingsHeight, 120), 440))
            } else {
                form.frame(height: 360)
            }
        }
    }

    @ViewBuilder private var curseForgeStatus: some View {
        let unresolved = files == nil && !prepared.curseForgeFiles.isEmpty
        if unresolved || error != nil {
            Section {
                if resolving {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(Messages.AppImportInstanceView.resolvingModpackFiles.localized) }
                } else if unresolved {
                    LabeledContent {
                        if model.curseForgeConfigured { Button(Messages.AppImportInstanceView.resolveFileManifest.localized) { resolve() } }
                    } label: {
                        Text(Messages.AppImportInstanceView.curseforgeManifestRequired.localized)
                        if !model.curseForgeConfigured { Text(Messages.AppImportInstanceView.configureAPIKeyInstruction.localized) }
                    }
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
            }
        }
    }

    @ViewBuilder private var manualDownloads: some View {
        let manual = chosenFiles.filter(\.requiresManualDownload)
        if !manual.isEmpty {
            Section {
                ForEach(manual) { item in
                    CurseForgeFileRow(file: item.file, title: item.project.name, page: item.pageURL, manual: true,
                                      selectedURL: Binding(get: { manualFiles[item.id] }, set: { manualFiles[item.id] = $0 }), compact: true)
                }
            } header: {
                HStack {
                    Text(Messages.AppImportInstanceView.manualDownloads.localized)
                    Spacer()
                    Text("\(manual.filter { manualFiles[$0.id] != nil }.count) / \(manual.count)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var optionalContent: some View {
        let packFiles = prepared.optionalFiles
        let curse = optionalCurseFiles
        if !packFiles.isEmpty || !curse.isEmpty {
            Section {
                ForEach(packFiles) { file in
                    Toggle(isOn: Binding(get: { !excludedOptional.contains(file.path) }, set: { if $0 { excludedOptional.remove(file.path) } else { excludedOptional.insert(file.path) } })) {
                        ImportOptionLabel(title: (file.path as NSString).lastPathComponent, detail: file.size.map { LocalizedFormat.bytes($0) })
                    }
                }
                ForEach(curse) { item in
                    Toggle(isOn: Binding(get: { !excluded.contains(item.id) }, set: { if $0 { excluded.remove(item.id) } else { excluded.insert(item.id) } })) {
                        ImportOptionLabel(title: item.project.name, detail: LocalizedFormat.bytes(item.file.fileLength))
                    }
                }
            } header: { Text(Messages.AppImportInstanceView.optionalContent.localized) }
        }
    }

    @ViewBuilder private var arguments: some View {
        let game = prepared.instance.extraGameArguments ?? ""
        let jvm = prepared.instance.extraJVMArguments
        if !game.isEmpty || !jvm.isEmpty {
            Section {
                if !game.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Messages.AppImportInstanceView.gameArguments.localized)
                        argumentText(game)
                    }
                }
                if !jvm.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(Messages.AppImportInstanceView.preserveCustomJVMArguments.localized, isOn: $keepJVMArguments)
                        argumentText(jvm)
                    }
                }
            } header: { Text(Messages.AppImportInstanceView.advanced.localized) }
        }
    }

    private func argumentText(_ value: String) -> some View {
        Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the pack sets for memory and the window. A Ruri export fixes
    /// every value; other formats only carry what they override, and the rest
    /// already follows the global settings, so there is nothing to show.
    private var packLaunchSettings: [(key: LaunchSettingKey, text: String)] {
        let instance = prepared.instance
        let memory = instance.launchOverrides.map { $0.memory?.maximumMB } ?? instance.memoryMB
        let window = instance.launchOverrides.map { $0.window.map { ($0.width, $0.height) } } ?? (instance.width, instance.height)
        var result: [(key: LaunchSettingKey, text: String)] = []
        if let memory { result.append((.memory, "\(Messages.AppImportInstanceView.memory.localized) \(memory) MB")) }
        if let window { result.append((.window, "\(Messages.AppImportInstanceView.window.localized) \(window.0) × \(window.1)")) }
        return result
    }
    /// For a new instance the player can hand the pack's values to the global
    /// settings instead; an export or an update keeps them as they are.
    @ViewBuilder private var launchSettings: some View {
        let values = packLaunchSettings
        let summary = values.map(\.text).joined(separator: " · ")
        if !values.isEmpty {
            if prepared.instance.launchOverrides != nil && updateTarget == nil {
                Toggle(isOn: Binding(get: { inheritedSettings.isEmpty }, set: { inheritedSettings = $0 ? [] : Set(values.map(\.key)) })) {
                    Text(Messages.AppImportInstanceView.usePackLaunchSettings.localized); Text(summary)
                }
            } else {
                LabeledContent(Messages.AppImportInstanceView.launchSettings.localized, value: summary)
            }
        }
    }
    private func resolve() {
        resolving = true; error = nil
        task = Task {
            do {
                let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).resolve(prepared.curseForgeFiles)
                try Task.checkCancellation(); files = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            resolving = false
        }
    }
}

private struct ImportOptionLabel: View {
    let title: String
    let detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).lineLimit(1).truncationMode(.middle)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ImportContentEntry: Identifiable {
    enum Source {
        case bundled, download, manual
        var symbol: String { switch self { case .bundled: "shippingbox"; case .download: "arrow.down.circle"; case .manual: "hand.raised" } }
        var title: String {
            switch self {
            case .bundled: Messages.AppImportInstanceView.bundledInPack.localized
            case .download: Messages.AppCurseForgeFilePicker.automaticDownload.localized
            case .manual: Messages.AppCurseForgeFilePicker.manualDownload.localized
            }
        }
    }
    let id: String
    let name: String
    var detail: String?
    let kind: ContentKind?
    let size: Int64?
    let source: Source
    init(id: String, name: String, detail: String? = nil, kind: ContentKind?, size: Int64?, source: Source) {
        self.id = id; self.name = name; self.detail = detail; self.kind = kind; self.size = size; self.source = source
    }
    /// A pack file named by its path; the top folder decides its kind.
    init(path: String, size: Int64?, source: Source) {
        let folder = path.split(separator: "/").first.map(String.init)
        self.init(id: "\(source):\(path)", name: (path as NSString).lastPathComponent, kind: ContentKind.allCases.first { $0.folder == folder }, size: size, source: source)
    }
}

enum ImportContentGroup: Identifiable, Hashable {
    case all, kind(ContentKind), other
    var id: String { switch self { case .all: "all"; case .kind(let kind): kind.rawValue; case .other: "other" } }
    var title: String {
        switch self {
        case .all: Messages.AppImportInstanceView.allContent.localized
        case .kind(let kind): kind.title
        case .other: Messages.AppImportInstanceView.otherContent.localized
        }
    }
    func contains(_ entry: ImportContentEntry) -> Bool {
        switch self { case .all: true; case .kind(let kind): entry.kind == kind; case .other: entry.kind == nil }
    }
}

/// Searchable, one line per file, so a pack with hundreds of mods stays
/// out of the way until the player asks for it.
private struct ImportContentBrowser: View {
    let contents: [ImportContentEntry]
    @State private var group: ImportContentGroup
    @State private var query = ""
    init(contents: [ImportContentEntry], group: ImportContentGroup) { self.contents = contents; _group = State(initialValue: group) }
    private var groups: [ImportContentGroup] {
        [.all] + ContentKind.allCases.filter { kind in contents.contains { $0.kind == kind } }.map(ImportContentGroup.kind) + (contents.contains { $0.kind == nil } ? [.other] : [])
    }
    private struct Shelf: Identifiable { let group: ImportContentGroup; let entries: [ImportContentEntry]; var id: String { group.id } }
    private var sections: [Shelf] {
        let matches = contents.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.detail?.localizedCaseInsensitiveContains(query) == true }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let shown = group == .all ? Array(groups.dropFirst()) : [group]
        return shown.map { Shelf(group: $0, entries: matches.filter($0.contains)) }.filter { !$0.entries.isEmpty }
    }
    var body: some View {
        let sections = sections
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker(selection: $group) { ForEach(groups) { Text($0.title).tag($0) } } label: { EmptyView() }
                    .pickerStyle(.segmented).labelsHidden()
                NativeSearchField(text: $query, prompt: Messages.AppImportInstanceView.searchContent.localized)
            }.padding(12)
            Divider()
            if sections.isEmpty {
                ContentUnavailableView(Messages.AppImportInstanceView.noMatchingContent.localized, systemImage: "magnifyingglass").frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections) { section in
                        if group == .all {
                            Section(section.group.title) { ForEach(section.entries) { ImportContentRow(entry: $0) } }
                        } else {
                            ForEach(section.entries) { ImportContentRow(entry: $0) }
                        }
                    }
                }.listStyle(.inset)
            }
        }.frame(width: 420, height: 460)
    }
}

private struct ImportContentRow: View {
    let entry: ImportContentEntry
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.source.symbol).foregroundStyle(.secondary).frame(width: 16).help(entry.source.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                if let detail = entry.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }.help(entry.detail ?? entry.name)
            Spacer(minLength: 8)
            if let size = entry.size { Text(LocalizedFormat.bytes(size)).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }.padding(.vertical, 2)
    }
}
