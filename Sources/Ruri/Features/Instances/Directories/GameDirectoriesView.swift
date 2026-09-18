import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// The library's folder menu: pick the instance folder the library shows, or
/// add and manage folders.
struct DirectoryMenuItems: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Picker(Messages.AppGameDirectoriesView.instanceFolders.localized, selection: Binding(get: { model.selectedDirectoryID }, set: { model.selectDirectory($0) })) {
            Text(Messages.AppGameDirectoriesView.defaultInstanceFolder.localized).tag(GameDirectory.defaultID)
            ForEach(model.state.gameDirectories ?? []) { directory in Text(directory.name).tag(directory.id) }
        }
        .pickerStyle(.inline)
        .disabled(model.busy)
        Divider()
        DirectoryCommands()
    }
}

/// Commands for the instance folders, under the folder list in that menu.
struct DirectoryCommands: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            if model.paths.isMinecraftDirectory(model.selectedDirectoryID) {
                Button(Messages.AppGameDirectoriesView.refreshVersions.localized, systemImage: "arrow.clockwise") { Task { await model.refreshMinecraftFolder() } }
            }
            Button(Messages.AppGameDirectoriesView.addFolder.localized, systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
            Button(Messages.AppGameDirectoriesView.manageFolders.localized, systemImage: "folder.badge.gearshape") { model.showDirectories = true }
        }
        .labelStyle(.titleAndIcon)
        .disabled(model.busy)
    }
}

struct GameDirectoriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var refreshing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Messages.AppGameDirectoriesView.instanceFolders.localized).font(.title2.weight(.semibold))
                Spacer()
                Button(Messages.AppGameDirectoriesView.addFolder.localized, systemImage: "plus") { model.chooseMinecraftDirectory() }
                    .disabled(model.busy || model.readOnly)
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                List(selection: $selection) {
                    Section(Messages.FolderExperience.activeFolders.localized) {
                        folderLabel(Messages.AppGameDirectoriesView.defaultInstanceFolder.localized, id: GameDirectory.defaultID, symbol: "internaldrive")
                            .tag(GameDirectory.defaultID)
                        ForEach(model.state.gameDirectories ?? []) { directory in
                            folderLabel(directory.name, id: directory.id, symbol: "folder")
                                .tag(directory.id)
                        }
                    }
                    if let detached = model.state.detachedMinecraftFolders, !detached.isEmpty {
                        Section(Messages.AppGameDirectoriesView.removedFolders.localized) {
                            ForEach(detached) { folder in
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(folder.directory.name).lineLimit(2)
                                        Text((folder.directory.url.path as NSString).abbreviatingWithTildeInPath)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                } icon: { Image(systemName: "folder.badge.minus") }
                                    .padding(.vertical, 5).tag(folder.id).help(folder.directory.url.path)
                            }
                        }
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor)).frame(width: 220)
                    .accessibilityLabel(Messages.AppGameDirectoriesView.instanceFolders.localized)
                Divider()
                Group {
                    if selection == GameDirectory.defaultID {
                        GameDirectoryDetail(directory: nil, openLibrary: openLibrary)
                    } else if let directory = model.state.gameDirectories?.first(where: { $0.id == selection }) {
                        GameDirectoryDetail(directory: directory, openLibrary: openLibrary).id(directory.id)
                    } else if let folder = model.state.detachedMinecraftFolders?.first(where: { $0.id == selection }) {
                        DetachedMinecraftFolderDetail(folder: folder)
                    } else {
                        ContentUnavailableView(Messages.FolderExperience.noSelection.localized, systemImage: "folder")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Button(Messages.AppGameDirectoriesView.checkAvailability.localized, systemImage: "arrow.clockwise") {
                    refreshing = true
                    Task { await model.refreshDirectoryAvailability(); refreshing = false }
                }.disabled(refreshing || model.busy)
                if refreshing { ProgressView().controlSize(.small) }
                Spacer()
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 800, height: 600)
        .task { selection = model.selectedDirectoryID; await model.refreshDirectoryAvailability() }
    }

    private func folderLabel(_ name: String, id: UUID, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).fontWeight(.medium).lineLimit(2)
                Text(model.directoryErrors[id] == nil
                     ? Messages.AppGameDirectoriesView.instanceCount(Int64(model.state.instances.filter { ($0.directoryID ?? GameDirectory.defaultID) == id }.count)).localized
                     : Messages.FolderExperience.unavailable.localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.directoryErrors[id] != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(Messages.FolderExperience.unavailable.localized)
            } else if model.selectedDirectoryID == id {
                Image(systemName: "checkmark").font(.caption.weight(.semibold))
                    .help(Messages.FolderExperience.currentFolder.localized)
            }
        }.padding(.vertical, 5)
    }

    private func openLibrary(_ id: UUID) {
        model.selectDirectory(id)
        dismiss()
    }
}

private struct GameDirectoryDetail: View {
    @Environment(AppModel.self) private var model
    let directory: GameDirectory?
    let openLibrary: (UUID) -> Void
    @State private var name: String
    init(directory: GameDirectory?, openLibrary: @escaping (UUID) -> Void) {
        self.directory = directory; self.openLibrary = openLibrary
        _name = State(initialValue: directory?.name ?? "")
    }
    private var id: UUID { directory?.id ?? GameDirectory.defaultID }
    private var title: String { directory?.name ?? Messages.AppGameDirectoriesView.defaultInstanceFolder.localized }
    private var url: URL { directory?.url ?? model.basePaths.instances }
    private var count: Int { model.state.instances.filter { ($0.directoryID ?? GameDirectory.defaultID) == id }.count }
    private var issue: String? { model.directoryErrors[id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: directory == nil ? "internaldrive.fill" : "folder.fill")
                    .font(.system(size: 36)).foregroundStyle(.tint).symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.weight(.semibold)).lineLimit(2)
                    if model.selectedDirectoryID == id {
                        Label(Messages.FolderExperience.currentFolder.localized, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                    } else { Text(Messages.AppGameDirectoriesView.instanceCount(Int64(count)).localized).foregroundStyle(.secondary) }
                }
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
            Form {
                Section {
                    if directory != nil {
                        HStack(alignment: .top, spacing: 16) {
                            Text(Messages.FolderExperience.name.localized).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField(Messages.FolderExperience.name.localized, text: $name)
                                        .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                                        .accessibilityLabel(Messages.FolderExperience.name.localized).onSubmit(rename)
                                    if name != title {
                                        Button(Messages.AppGameDirectoriesView.saveName.localized, action: rename)
                                            .disabled((try? GameDirectory.validName(name)) == nil)
                                    }
                                }
                                Text(Messages.FolderExperience.nameHelp.localized).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 3)
                    }
                    LabeledContent(Messages.FolderExperience.contents.localized, value: Messages.AppGameDirectoriesView.instanceCount(Int64(count)).localized)
                    LabeledContent(Messages.FolderExperience.status.localized) {
                        Label(issue == nil ? Messages.FolderExperience.available.localized : Messages.FolderExperience.unavailable.localized,
                              systemImage: issue == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue == nil ? Color.secondary : .orange)
                    }
                } footer: {
                    if directory == nil { Text(Messages.FolderExperience.defaultHelp.localized) }
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(url.path).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button(Messages.AppGameDirectoriesView.showInFinder.localized, systemImage: "folder") { reveal() }.disabled(issue != nil)
                    }.padding(.vertical, 4)
                } header: { Text(Messages.FolderExperience.folderLocation.localized) }
                if let issue {
                    Section {
                        Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                        Button(Messages.AppGameDirectoriesView.relocateOriginal.localized, systemImage: "folder.badge.questionmark", action: relocate)
                    } footer: { Text(Messages.FolderExperience.reconnectHelp.localized) }
                }
                Section {
                    Button(Messages.FolderExperience.showLibrary.localized, systemImage: "square.grid.2x2") { openLibrary(id) }
                }
                if let directory {
                    Section {
                        Button(Messages.AppGameDirectoriesView.removeFromList.localized, role: .destructive) {
                            model.changeDirectory { try GameDirectoryStore.remove(directory.id, paths: $0) }
                        }.disabled(count > 0 && !directory.isMinecraft)
                    } footer: {
                        Text(directory.isMinecraft ? Messages.FolderExperience.removeHelp.localized : Messages.FolderExperience.managedRemoveHelp.localized)
                    }
                }
            }.formStyle(.grouped).disabled(model.busy || model.readOnly)
        }.onChange(of: directory?.name) { name = directory?.name ?? "" }
    }
    private func rename() {
        guard let directory, name != directory.name, (try? GameDirectory.validName(name)) != nil else { return }
        model.changeDirectory { try GameDirectoryStore.rename(directory.id, name: name, paths: $0) }
    }
    private func reveal() {
        do { try directory?.validateAvailability(); NSWorkspace.shared.open(url) }
        catch { model.error = error.localizedDescription }
    }
    private func relocate() {
        guard let directory else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppGameDirectoriesView.chooseOriginalLocation(directory.name).localized
        panel.prompt = Messages.AppGameDirectoriesView.relocate.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.changeDirectory { try GameDirectoryStore.relocate(directory.id, to: url, paths: $0) }
    }
}

private struct DetachedMinecraftFolderDetail: View {
    @Environment(AppModel.self) private var model
    let folder: DetachedMinecraftFolder
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "folder.badge.minus").font(.system(size: 36)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.directory.name).font(.title2.weight(.semibold)).lineLimit(2)
                    Text(Messages.FolderExperience.retainedFolder.localized).foregroundStyle(.secondary)
                }
            }.padding(24)
            Form {
                Section {
                    LabeledContent(Messages.FolderExperience.savedSettings.localized, value: Messages.AppGameDirectoriesView.instanceCount(Int64(folder.instances.count)).localized)
                    Text(folder.directory.url.path).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } footer: { Text(Messages.FolderExperience.removeHelp.localized) }
                Section {
                    Button(Messages.AppGameDirectoriesView.readdFolder.localized, systemImage: "plus") {
                        model.restoreMinecraftDirectory(folder, at: folder.directory.resolvingBookmark().url)
                    }
                    Button(Messages.AppGameDirectoriesView.chooseNewLocation.localized, systemImage: "folder", action: relocate)
                }
            }.formStyle(.grouped).disabled(model.busy || model.readOnly)
        }
    }
    private func relocate() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false
        panel.prompt = Messages.AppGameDirectoriesView.readdFolder.localized
        panel.message = Messages.AppGameDirectoriesView.relocateFolder(folder.directory.name).localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.restoreMinecraftDirectory(folder, at: url)
    }
}
