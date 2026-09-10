import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

extension AppModel {
    func chooseInstanceImport() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.zip, UTType(filenameExtension: "mrpack") ?? .data]
        panel.message = "选择实例目录或整合包：Ruri、Prism/MultiMC、Modrinth、CurseForge、HMCL 或 MCBBS。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPack(url)
    }
    func prepareInstanceImport(_ url: URL) {
        guard !busy else { return }
        perform("读取 \(url.lastPathComponent)") { [self] id in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importingInstance = try await InstanceTransfer(paths: paths).prepare(url) { [weak self] value in Task { @MainActor in self?.progress(id, value) } }
        }
    }
    func cancelImport(_ prepared: PreparedInstanceImport) {
        importingInstance = nil
        Task { await InstanceTransfer(paths: paths).discard(prepared) }
    }
    func finishImport(_ prepared: PreparedInstanceImport, name: String, keepJVMArguments: Bool, curseFiles: [PlannedCurseFile] = [], manualFiles: [Int: URL] = [:]) {
        guard !busy else { return }
        importingInstance = nil; page = .downloads
        perform("导入 \(name)") { [self] id in
            let service = InstanceTransfer(paths: paths)
            do {
                let content = try await CurseForgeService(apiKey: "").materialize(curseFiles, paths: paths, downloader: installer.downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
                let instance = try await service.install(prepared, name: name, importJVMArguments: keepJVMArguments, content: content, installer: installer, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                state.instances.append(instance); select(instance); notice = "\(instance.name) 已导入"
                await service.discard(prepared)
            } catch { importingInstance = prepared; throw error }
        }
    }
    func export(_ instance: GameInstance, to url: URL, format: InstanceExportFormat, includeWorlds: Bool, details: ModpackExportDetails = .init()) {
        guard !isInstanceInUse(instance.id) else { return }
        perform("导出 \(instance.name)", instanceID: instance.id) { [self] id in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await InstanceTransfer(paths: paths).export(instance, to: url, format: format, includeWorlds: includeWorlds, details: details) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
            notice = "\(instance.name) 已导出"; NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
