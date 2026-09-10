import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

extension AppModel {
    func chooseMinecraftDirectory() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.json]
        panel.message = "选择已有的 Minecraft 目录、versions 文件夹，或其中一个版本。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("读取已有 Minecraft 版本") { [self] _ in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            minecraftDirectory = try await MinecraftDirectoryReader().scan(url)
        }
    }
}
