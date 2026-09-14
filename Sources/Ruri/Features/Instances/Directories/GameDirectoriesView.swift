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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: Messages.AppGameDirectoriesView.instanceFolders.localized)
                Spacer()
                Button(Messages.AppGameDirectoriesView.addFolder.localized, systemImage: "plus") { model.chooseMinecraftDirectory() }.disabled(model.busy)
            }
            Text(Messages.AppGameDirectoriesView.folderUsage.localized)
                .font(.callout).foregroundStyle(.secondary)
            Text(Messages.AppGameDirectoriesView.removedFolderRecovery.localized)
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    Surface {
                        HStack(alignment: .top) {
                            Image(systemName: "internaldrive").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(Messages.AppGameDirectoriesView.defaultInstanceFolder.localized).font(.headline)
                                Text(model.basePaths.instances.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                Text(Messages.AppGameDirectoriesView.instanceCount(Int64(model.state.instances.filter { $0.directoryID == nil || $0.directoryID == GameDirectory.defaultID }.count)).localized).font(.caption)
                            }
                            Spacer()
                            Button(model.selectedDirectoryID == GameDirectory.defaultID ? Messages.AppGameDirectoriesView.selected.localized : Messages.AppGameDirectoriesView.select.localized) { model.selectDirectory(GameDirectory.defaultID) }
                                .disabled(model.busy || model.selectedDirectoryID == GameDirectory.defaultID)
                        }
                    }
                    ForEach(model.state.gameDirectories ?? []) { directory in GameDirectoryRow(directory: directory) }
                    if let detached = model.state.detachedMinecraftFolders, !detached.isEmpty {
                        Text(Messages.AppGameDirectoriesView.removedFolders.localized).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        ForEach(detached) { folder in DetachedMinecraftFolderRow(folder: folder) }
                    }
                }.padding(2)
            }
            HStack {
                Button(Messages.AppGameDirectoriesView.checkAvailability.localized, systemImage: "arrow.clockwise") { Task { await model.refreshDirectoryAvailability() } }
                Spacer()
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 690, height: 560)
        .task { await model.refreshDirectoryAvailability() }
    }
}

private struct DetachedMinecraftFolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: DetachedMinecraftFolder
    var body: some View {
        Surface {
            HStack(alignment: .top) {
                Image(systemName: "folder.badge.minus").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.directory.name).font(.headline)
                    Text(folder.directory.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(Messages.AppGameDirectoriesView.preserveDetachedSettings(Int64(folder.instances.count)).localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.AppGameDirectoriesView.readdFolder.localized) {
                    model.restoreMinecraftDirectory(folder, at: folder.directory.resolvingBookmark().url)
                }.disabled(model.busy)
                Menu {
                    Group {
                        Button(Messages.AppGameDirectoriesView.chooseNewLocation.localized, systemImage: "folder.badge.plus") {
                            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false; panel.prompt = Messages.AppGameDirectoriesView.readdFolder.localized
                            panel.message = Messages.AppGameDirectoriesView.relocateFolder(folder.directory.name).localized
                            guard panel.runModal() == .OK, let url = panel.url else { return }
                            model.restoreMinecraftDirectory(folder, at: url)
                        }
                    }.labelStyle(.titleAndIcon)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize().disabled(model.busy)
            }
        }
    }
}

private struct GameDirectoryRow: View {
    @Environment(AppModel.self) private var model
    let directory: GameDirectory
    @State private var name: String
    init(directory: GameDirectory) { self.directory = directory; _name = State(initialValue: directory.name) }
    private var count: Int { model.state.instances.filter { $0.directoryID == directory.id }.count }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "folder").font(.title2)
                    TextField(Messages.AppGameDirectoriesView.folderName.localized, text: $name).textFieldStyle(.roundedBorder).onSubmit(rename)
                    if name != directory.name { Button(Messages.AppGameDirectoriesView.saveName.localized, action: rename).disabled(model.busy) }
                    Spacer()
                    Button(model.selectedDirectoryID == directory.id ? Messages.AppGameDirectoriesView.selected.localized : Messages.AppGameDirectoriesView.select.localized) { model.selectDirectory(directory.id) }
                        .disabled(model.busy || model.selectedDirectoryID == directory.id)
                }
                Text(directory.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Label(model.directoryErrors[directory.id] == nil ? Messages.AppGameDirectoriesView.availableInstanceCount(Int64(count)).localized : Messages.AppGameDirectoriesView.unavailableInstanceCount(Int64(count)).localized, systemImage: model.directoryErrors[directory.id] == nil ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(model.directoryErrors[directory.id] == nil ? Color.secondary : .orange)
                    Spacer()
                    Button(Messages.AppGameDirectoriesView.showInFinder.localized) { do { try directory.validateAvailability(); NSWorkspace.shared.open(directory.url) } catch { model.error = error.localizedDescription } }
                    Menu {
                        Group {
                            Button(Messages.AppGameDirectoriesView.relocateOriginal.localized, systemImage: "folder") { relocate() }
                            Button(Messages.AppGameDirectoriesView.removeFromList.localized, systemImage: "minus.circle") { model.changeDirectory { try GameDirectoryStore.remove(directory.id, paths: $0) } }.disabled(count > 0 && !directory.isMinecraft)
                        }.labelStyle(.titleAndIcon)
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize().disabled(model.busy)
                }
                if let issue = model.directoryErrors[directory.id] { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: directory.name) { name = directory.name }
    }
    private func rename() { model.changeDirectory { try GameDirectoryStore.rename(directory.id, name: name, paths: $0) } }
    private func relocate() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppGameDirectoriesView.chooseOriginalLocation(directory.name).localized; panel.prompt = Messages.AppGameDirectoriesView.relocate.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.changeDirectory { try GameDirectoryStore.relocate(directory.id, to: url, paths: $0) }
    }
}
