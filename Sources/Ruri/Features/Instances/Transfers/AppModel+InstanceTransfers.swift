import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

extension AppModel {
    func chooseInstanceImport() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.zip, UTType(filenameExtension: "mrpack") ?? .data]
        panel.message = Messages.AppAppModelInstanceTransfers.panelText1.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPack(url)
    }
    func prepareInstanceImport(_ url: URL) {
        guard !busy else { return }
        perform(Messages.AppAppModelInstanceTransfers.prepareInstanceImportText1(String(describing: url.lastPathComponent))) { [self] id in
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
        perform(Messages.AppAppModelInstanceTransfers.finishImportText1(String(describing: name))) { [self] id in
            let service = InstanceTransfer(paths: paths)
            do {
                try await service.validateDestination(prepared, name: name)
                let content = try await CurseForgeService(apiKey: "").materialize(curseFiles, paths: paths, downloader: installer.downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
                let instance = try await service.install(prepared, name: name, importJVMArguments: keepJVMArguments, content: content, installer: installer, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                if instance.repositoryVersionID != nil { acceptState(try StateStore.load(basePaths)) }
                else { state.instances.append(instance); select(instance) }
                notice = Messages.AppAppModelInstanceTransfers.instanceText1(String(describing: instance.name)).localized
                await service.discard(prepared)
            } catch {
                importingInstance = prepared
                if let failure = error as? RepositoryImportFailure { notice = failure.message; noticeFileURL = failure.preservedFiles }
                throw error
            }
        }
    }
    func export(_ instance: GameInstance, to url: URL, format: InstanceExportFormat, includeWorlds: Bool, details: ModpackExportDetails = .init()) {
        guard !isInstanceInUse(instance.id) else { return }
        perform(Messages.AppAppModelInstanceTransfers.exportText1(String(describing: instance.name)), instanceID: instance.id) { [self] id in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await InstanceTransfer(paths: paths).export(instance, to: url, format: format, includeWorlds: includeWorlds, details: details) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
            notice = Messages.AppAppModelInstanceTransfers.scopedText1(String(describing: instance.name)).localized; NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
