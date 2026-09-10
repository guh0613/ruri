import SwiftUI
import AppKit
import RuriCore

extension AppModel {
    func chooseMinecraftDirectory() {
        guard !busy, !readOnly else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "添加文件夹"
        panel.message = "选择已有 Minecraft 文件夹，或新建一个文件夹。已有版本会直接出现在实例列表中。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save()
        guard !readOnly else { return }
        let base = basePaths
        perform("添加游戏文件夹") { [self] _ in
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
