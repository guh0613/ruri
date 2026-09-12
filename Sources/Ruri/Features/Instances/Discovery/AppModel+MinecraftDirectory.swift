import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

extension AppModel {
    func restoreMinecraftDirectory(_ folder: DetachedMinecraftFolder, at url: URL) {
        guard !busy, !readOnly else { return }
        save()
        guard !readOnly else { return }
        let base = basePaths
        perform(Messages.AppAppModelMinecraftDirectory.recoverGameFolder) { [self] _ in
            let result = try await Task.detached(priority: .userInitiated) {
                try MinecraftFolderStore.restore(folder.id, from: url, paths: base)
            }.value
            acceptState(result); showDirectories = false; page = .library
            await refreshDirectoryAvailability()
        }
    }

    func chooseMinecraftDirectory() {
        guard !busy, !readOnly else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = Messages.AppAppModelMinecraftDirectory.addGameFolder.localized
        panel.message = Messages.AppAppModelMinecraftDirectory.folderSelectionHelp.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save()
        guard !readOnly else { return }
        let base = basePaths
        perform(Messages.AppAppModelMinecraftDirectory.addGameFolderEntry) { [self] _ in
            let result = try await Task.detached(priority: .userInitiated) {
                try MinecraftFolderStore.add(name: url.lastPathComponent, url: url, paths: base)
            }.value
            acceptState(result); showDirectories = false; page = .library
            await refreshDirectoryAvailability()
        }
    }

    func refreshMinecraftFolder() async {
        guard !busy, !readOnly else { return }
        save()
        guard !readOnly else { return }
        let base = basePaths, selected = selectedDirectoryID
        guard paths.isMinecraftDirectory(selected) else { return }
        do {
            _ = try await Task.detached(priority: .utility) { try MinecraftFolderStore.refresh(selected, paths: base) }.value
            // Merge through save if preferences changed while discovery was running.
            if state != persistedState { save() }
            guard !readOnly else { return }
            acceptState(try StateStore.load(base))
            directoryErrors.removeValue(forKey: selected)
        } catch { directoryErrors[selected] = error.localizedDescription }
    }
}
