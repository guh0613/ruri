import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

extension AppModel {
    func refreshMinecraftFolderSuggestions(force: Bool = false) async {
        if let task = minecraftFolderDiscoveryTask { _ = try? await task.value; return }
        if !force, let date = minecraftFolderDiscoveryDate, Date().timeIntervalSince(date) < 300 { return }
        discoveringMinecraftLocations = true; minecraftFolderDiscoveryError = nil
        let task = Task.detached(priority: .utility) { try MinecraftFolderDiscovery.commonLocations() }
        minecraftFolderDiscoveryTask = task
        defer { discoveringMinecraftLocations = false; minecraftFolderDiscoveryTask = nil }
        do {
            // Keep this small scan alive if its sheet closes, so reopening can
            // reuse the result. Registration labels are never cached here.
            detectedMinecraftLocations = try await task.value
            minecraftFolderDiscoveryDate = Date()
        } catch {
            if !(error is CancellationError) { minecraftFolderDiscoveryError = error.localizedDescription }
        }
    }

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
        showAddDirectory = true
    }

    func addMinecraftDirectory(name: String, at url: URL, expectedDirectory: GameDirectory? = nil,
                               failed: @escaping @MainActor @Sendable (String) -> Void,
                               completed: @escaping @MainActor @Sendable (UUID) -> Void) {
        guard !busy, !readOnly else { return }
        save()
        guard !readOnly else { return }
        let base = basePaths
        perform(Messages.AppAppModelMinecraftDirectory.addGameFolderEntry, presentErrors: false) { [self] _ in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    // Recheck the selection before committing; preview never writes metadata.
                    try expectedDirectory?.validateAvailability()
                    let preview = try MinecraftFolderDiscovery.inspect(url)
                    guard preview.count == 1, preview[0].directory.path == url.standardizedFileURL.resolvingSymlinksInPath().path else {
                        throw RuriError.message(Messages.FolderExperience.noFolderFound)
                    }
                    if let existing = try StateStore.load(base).gameDirectories?.first(where: {
                        $0.url.standardizedFileURL.resolvingSymlinksInPath().path == preview[0].directory.path
                    }) {
                        return try GameDirectoryStore.select(existing.id, paths: base)
                    }
                    return try MinecraftFolderStore.add(name: name, url: url, paths: base)
                }.value
                acceptState(result)
                await refreshDirectoryAvailability()
                if let id = result.selectedDirectoryID { completed(id) }
            } catch { failed(error.localizedDescription); throw error }
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
