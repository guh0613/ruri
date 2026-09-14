import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// The library as a content column of instances beside the chosen instance's
/// page, like Mail. The column's title menu switches the instance folder, its
/// toolbar section holds import, a filter field sits on top of the list and
/// the add button beneath it, as in Reminders.
struct LibraryView<Sidebar: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @ViewBuilder var sidebar: Sidebar
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var deleteTarget: GameInstance?
    private var filtered: [GameInstance] {
        model.directoryInstances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.gameVersion.contains(search) }
            .sorted { $0.favorite != $1.favorite ? $0.favorite : $0.createdAt > $1.createdAt }
    }
    private var current: GameInstance? { filtered.first { $0.id == selectedID } ?? filtered.first }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            listColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
                .navigationTitle(model.page.title)
                .navigationSubtitle("\(model.selectedDirectoryName) · \(countLabel)")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        importMenu
                        Button { model.showCreate = true } label: { Label(Messages.AppLibraryView.newInstance.localized, systemImage: "plus") }
                            .help(Messages.AppLibraryView.newInstanceShortcut.localized)
                            .disabled(model.busy)
                    }
                }
        } detail: {
            detailColumn
                .toolbarBackground(.hidden, for: .windowToolbar)
                .toolbar { RootToolbar(model: model) }
        }
        .confirmationDialog(Messages.AppLibraryView.moveInstanceToTrashConfirmation.localized, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button(Messages.AppLibraryView.moveToTrash.localized, role: .destructive) { if let target = deleteTarget { model.trash(target) }; deleteTarget = nil }
        } message: { Text(deleteTarget?.repositoryVersionID != nil ? Messages.AppLibraryView.managedVersionFolderTrashDetails.localized : (deleteTarget?.runDirectory ?? .isolated) != .isolated ? Messages.AppLibraryView.instanceTrashDetails.localized : Messages.AppLibraryView.instanceAndSharedFilesTrashDetails.localized) }
        .task(id: model.selectedDirectoryID) { await model.refreshDirectoryAvailability(); await model.refreshMinecraftFolder() }
        // Keep a row selected: start from the instance featured on the home
        // page, and move on when the selection is filtered out or trashed.
        .onChange(of: filtered.map(\.id), initial: true) { _, ids in
            guard selectedID.map(ids.contains) != true else { return }
            let preferred = model.selected?.id
            selectedID = preferred.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        }
        .onChange(of: selectedID) { _, id in if id == nil { selectedID = filtered.first?.id } }
    }

    private var countLabel: String {
        let total = model.directoryInstances.count
        guard !search.isEmpty else { return Messages.AppLibraryView.instanceCount(Int64(total)).localized }
        return Messages.AppLibraryView.filteredInstanceCount(Int64(filtered.count), Int64(total)).localized
    }

    private var importMenu: some View {
        Menu {
            Group {
                Button(Messages.AppLibraryView.importInstanceOrModpack.localized, systemImage: "square.and.arrow.down") { model.chooseInstanceImport() }
                Button(Messages.AppLibraryView.addGameFolder.localized, systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
            }.labelStyle(.titleAndIcon)
        } label: { Label(Messages.AppLibraryView.importContentAction.localized, systemImage: "square.and.arrow.down").labelStyle(.iconOnly) }
        .labelStyle(.titleAndIcon)
        .help(Messages.AppLibraryView.importInstanceModpackOrGameFolder.localized)
        .disabled(model.busy)
    }

    // MARK: Content column

    /// The folder pull-down and filter ride on top of the list, like the sort
    /// menu over Mail's message list, and scroll content fades beneath them.
    private var listColumn: some View {
        list.topScrollBar {
            VStack(spacing: 16) {
                LibraryFolderMenu()
                LibrarySearchField(text: $search, prompt: Messages.AppLibraryView.searchInstancesOrVersions.localized)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 12)
        }
    }

    /// Favorites get their own section only when there is something else to
    /// set them apart from. Double-clicking a row launches it, and Delete
    /// moves it to the Trash after confirming.
    private var list: some View {
        List(selection: $selectedID) {
            let favorites = filtered.filter(\.favorite)
            if favorites.isEmpty || favorites.count == filtered.count {
                rows(filtered)
            } else {
                Section(Messages.AppLibraryView.favorites.localized) { rows(favorites) }
                Section(Messages.AppLibraryView.otherInstances.localized) { rows(filtered.filter { !$0.favorite }) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay { if filtered.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let instance = instance(ids) {
                LibraryContextActions(instance: instance, onTrash: { deleteTarget = $0 }).labelStyle(.titleAndIcon)
            }
        } primaryAction: { ids in
            guard let instance = instance(ids) else { return }
            if model.activeSessions[instance.id] != nil { model.returnToGame(instance.id) }
            else if !model.busy, !model.isInstanceInUse(instance.id) { model.launch(instance) }
        }
        .onDeleteCommand {
            if let current, !model.busy, !model.isInstanceInUse(current.id) { deleteTarget = current }
        }
    }

    private func rows(_ instances: [GameInstance]) -> some View {
        ForEach(instances) { instance in LibraryRow(instance: instance).tag(instance.id) }
    }

    private func instance(_ ids: Set<UUID>) -> GameInstance? {
        ids.first.flatMap { id in model.directoryInstances.first { $0.id == id } }
    }

    // MARK: Detail column

    private var detailColumn: some View {
        Group {
            if model.directoryInstances.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        folderNotices
                        emptyFolder
                    }.padding(28).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
                }
            } else if let instance = current {
                LibraryInstanceDetail(instance: instance, onTrash: { deleteTarget = $0 }) { folderNotices }.id(instance.id)
            } else {
                EmptyPanel(symbol: "magnifyingglass", title: Messages.AppLibraryView.noMatchingInstances.localized, detail: Messages.AppLibraryView.tryAnotherNameOrVersion.localized)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas(for: colorScheme))
    }

    @ViewBuilder private var folderNotices: some View {
        if let issue = model.directoryErrors[model.selectedDirectoryID] {
            VStack(alignment: .leading, spacing: 8) {
                Label(Messages.AppLibraryView.instanceFolderUnavailable.localized, systemImage: "externaldrive.badge.exclamationmark").font(.headline)
                Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack { Button(Messages.AppLibraryView.recheck.localized) { Task { await model.refreshDirectoryAvailability() } }; Button(Messages.AppLibraryView.manageFolders.localized) { model.showDirectories = true } }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        if model.paths.isMinecraftDirectory(model.selectedDirectoryID) {
            RepositoryImportRecoveryView(directoryID: model.selectedDirectoryID)
        }
    }

    private var emptyFolder: some View {
        ContentUnavailableView {
            Label(Messages.AppLibraryView.folderHasNoInstances.localized, systemImage: "square.grid.2x2")
        } description: {
            Text(Messages.AppLibraryView.createOrImportInstance.localized)
        } actions: {
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    Button(Messages.AppLibraryView.newInstance.localized) { model.showCreate = true }.buttonStyle(.borderedProminent)
                    Button(Messages.AppLibraryView.importModpack.localized) { model.chooseInstanceImport() }.buttonStyle(.bordered)
                }.fixedSize()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Messages.AppHomeView.existingGameFolderHint.localized).foregroundStyle(.secondary)
                    Button(Messages.AppHomeView.addExistingGameFolder.localized, systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
                        .buttonStyle(.link).disabled(model.readOnly)
                        .help(Messages.AppAppModelMinecraftDirectory.folderSelectionHelp.localized)
                }.font(.callout).fixedSize()
            }
        }
        .disabled(model.busy)
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

// MARK: - Row

private struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var body: some View {
        HStack(spacing: 10) {
            InstanceIcon(loader: instance.loader, size: 32, png: instance.iconPNG)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name).font(.body.weight(.medium)).lineLimit(1)
                Text(instance.gameVersion + " · " + instance.loaderLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.activeSessions[instance.id] != nil {
                Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent).accessibilityLabel(model.statusLabel(instance))
            } else if !model.statusIsNominal(instance) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(model.statusColor(instance)).accessibilityLabel(model.statusLabel(instance))
            }
        }
        .padding(.vertical, 4)
        .help(instance.name)
    }
}

/// The instance folder as a full-width pull-down that matches the search
/// field under it; its menu picks a folder or adds and manages folders.
private struct LibraryFolderMenu: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    var body: some View {
        Menu { DirectoryMenuItems() } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.selectedDirectoryName).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(.primary.opacity(hovering ? 0.10 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(model.busy)
        .onHover { hovering = $0 }
        .help(Messages.AppGameDirectoriesView.currentFolder(String(describing: model.selectedDirectoryName)).localized)
    }
}

private struct LibraryContextActions: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    let onTrash: (GameInstance) -> Void
    var body: some View {
        Button(Messages.AppLibraryView.showOnHome.localized, systemImage: "house") { model.select(instance) }
        Button(Messages.AppLibraryView.instanceSettings.localized, systemImage: "slider.horizontal.3") { model.editingInstance = instance }
        Button(Messages.AppLibraryView.manageModsAndResourcePacks.localized, systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
        Button(Messages.AppLibraryView.showInFinder.localized, systemImage: "folder") { model.reveal(instance) }
        Divider()
        Button(Messages.AppLibraryView.moveToTrash.localized, systemImage: "trash", role: .destructive) { onTrash(instance) }.disabled(model.busy || model.isInstanceInUse(instance.id))
    }
}

/// The system search field, which SwiftUI only offers in the toolbar, for
/// filtering the list column from its top edge as Settings does.
private struct LibrarySearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
    }
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    @MainActor final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ sender: NSSearchField) { text.wrappedValue = sender.stringValue }
    }
}
