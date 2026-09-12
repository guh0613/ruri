import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// Every instance in the selected folder, as a grid of cards or a list of
/// rows. The folder and count sit under the window title like a Finder
/// window, and the folder, layout, import and create controls are all icons
/// in the toolbar.
struct LibraryView: View {
    enum Layout: String { case grid, list }
    @Environment(AppModel.self) private var model
    @AppStorage("libraryLayout") private var layout = Layout.grid
    @State private var search = ""
    @State private var deleteTarget: GameInstance?
    private var filtered: [GameInstance] {
        model.directoryInstances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.gameVersion.contains(search) }
            .sorted { $0.favorite != $1.favorite ? $0.favorite : $0.createdAt > $1.createdAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                if model.directoryInstances.isEmpty {
                    emptyFolder
                } else if filtered.isEmpty {
                    EmptyPanel(symbol: "magnifyingglass", title: Messages.AppLibraryView.noMatchingInstances.localized, detail: Messages.AppLibraryView.tryAnotherNameOrVersion.localized)
                } else if layout == .grid {
                    grid
                } else {
                    list
                }
            }.padding(28)
        }
        .navigationSubtitle("\(model.selectedDirectoryName) · \(countLabel)")
        .searchable(text: $search, placement: .toolbar, prompt: Messages.AppLibraryView.searchInstancesOrVersions.localized)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                DirectoryMenu()
                Picker(Messages.AppLibraryView.layout.localized, selection: $layout) {
                    Label(Messages.AppLibraryView.grid.localized, systemImage: "square.grid.2x2").tag(Layout.grid)
                    Label(Messages.AppLibraryView.list.localized, systemImage: "list.bullet").tag(Layout.list)
                }.pickerStyle(.segmented).help(Messages.AppLibraryView.gridOrList.localized)
                Menu {
                    Button(Messages.AppLibraryView.importInstanceOrModpack.localized, systemImage: "square.and.arrow.down") { model.chooseInstanceImport() }
                    Button(Messages.AppLibraryView.addGameFolder.localized, systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
                } label: { Label(Messages.AppLibraryView.importContentAction.localized, systemImage: "square.and.arrow.down") }.help(Messages.AppLibraryView.importInstanceModpackOrGameFolder.localized).disabled(model.busy)
                Button { model.showCreate = true } label: { Label(Messages.AppLibraryView.newInstance.localized, systemImage: "plus") }.help(Messages.AppLibraryView.newInstanceShortcut.localized).disabled(model.busy)
            }
        }
        .confirmationDialog(Messages.AppLibraryView.moveInstanceToTrashConfirmation.localized, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button(Messages.AppLibraryView.moveToTrash.localized, role: .destructive) { if let target = deleteTarget { model.trash(target) }; deleteTarget = nil }
        } message: { Text(deleteTarget?.repositoryVersionID != nil ? Messages.AppLibraryView.managedVersionFolderTrashDetails.localized : (deleteTarget?.runDirectory ?? .isolated) != .isolated ? Messages.AppLibraryView.instanceTrashDetails.localized : Messages.AppLibraryView.instanceAndSharedFilesTrashDetails.localized) }
        .task(id: model.selectedDirectoryID) { await model.refreshDirectoryAvailability(); await model.refreshMinecraftFolder() }
    }

    private var countLabel: String {
        let total = model.directoryInstances.count
        guard !search.isEmpty else { return Messages.AppLibraryView.instanceCount(Int64(total)).localized }
        return Messages.AppLibraryView.filteredInstanceCount(Int64(filtered.count), Int64(total)).localized
    }

    private var emptyFolder: some View {
        ContentUnavailableView {
            Label(Messages.AppLibraryView.folderHasNoInstances.localized, systemImage: "square.grid.2x2")
        } description: {
            Text(Messages.AppLibraryView.createOrImportInstance.localized)
        } actions: {
            Button(Messages.AppLibraryView.newInstance.localized) { model.showCreate = true }.buttonStyle(.borderedProminent)
            Button(Messages.AppLibraryView.importModpack.localized) { model.chooseInstanceImport() }
        }
        .disabled(model.busy)
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
            ForEach(filtered) { instance in card(instance) }
            if search.isEmpty {
                DashedTile(symbol: "plus", title: Messages.AppLibraryView.newInstance.localized, detail: Messages.AppLibraryView.importModpackFromToolbar.localized) { model.showCreate = true }
                    .frame(minHeight: 150).disabled(model.busy)
            }
        }
    }

    private func card(_ instance: GameInstance) -> some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    iconButton(instance, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(instance.name).font(.headline).lineLimit(1)
                            if instance.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption2) }
                        }
                        Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    InstanceMenu(instance: instance, onTrash: { deleteTarget = $0 })
                }
                HStack(spacing: 10) {
                    TagPill(text: model.statusLabel(instance), color: model.statusColor(instance))
                    Text(model.memoryLabel(instance)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(instance.lastPlayedLabel).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                if let issue = instance.repositoryIssue { Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(3).help(issue) }
                Divider()
                HStack {
                    InstanceQuickActions(instance: instance)
                    Spacer()
                    LaunchButton(instance: instance)
                }
            }
        }
        .contextMenu { contextActions(instance) }
    }

    // MARK: List

    private var list: some View {
        Surface(padding: 0) {
            VStack(spacing: 0) {
                ForEach(filtered) { instance in
                    row(instance)
                    if instance.id != filtered.last?.id { Divider().padding(.leading, 74) }
                }
            }
        }
    }

    private func row(_ instance: GameInstance) -> some View {
        HStack(spacing: 14) {
            iconButton(instance, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(instance.name).font(.headline).lineLimit(1)
                    if instance.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption2) }
                }
                Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let issue = instance.repositoryIssue { Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(1).help(issue) }
            }
            Spacer(minLength: 12)
            TagPill(text: model.statusLabel(instance), color: model.statusColor(instance))
            Text(model.memoryLabel(instance)).font(.caption).foregroundStyle(.secondary).frame(width: 96, alignment: .trailing).lineLimit(1)
            Text(instance.lastPlayedLabel).font(.caption).foregroundStyle(.tertiary).frame(width: 110, alignment: .trailing).lineLimit(1)
            InstanceQuickActions(instance: instance)
            LaunchButton(instance: instance)
            InstanceMenu(instance: instance, onTrash: { deleteTarget = $0 })
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contextMenu { contextActions(instance) }
    }

    // MARK: Shared pieces

    private func iconButton(_ instance: GameInstance, size: CGFloat) -> some View {
        Button { model.editingInstance = instance } label: {
            InstanceIcon(loader: instance.loader, size: size, png: instance.iconPNG)
        }.buttonStyle(.plain).help(Messages.AppLibraryView.changeIconOrEditSettings.localized).accessibilityLabel(Messages.AppLibraryView.editIconAndSettings(instance.name).localized)
    }

    @ViewBuilder private func contextActions(_ instance: GameInstance) -> some View {
        Button(Messages.AppLibraryView.showOnHome.localized, systemImage: "house") { model.select(instance) }
        Button(Messages.AppLibraryView.instanceSettings.localized, systemImage: "slider.horizontal.3") { model.editingInstance = instance }
        Button(Messages.AppLibraryView.manageModsAndResourcePacks.localized, systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
        Button(Messages.AppLibraryView.showInFinder.localized, systemImage: "folder") { model.reveal(instance) }
        Divider()
        Button(Messages.AppLibraryView.moveToTrash.localized, systemImage: "trash", role: .destructive) { deleteTarget = instance }.disabled(model.busy || model.isInstanceInUse(instance.id))
    }
}
