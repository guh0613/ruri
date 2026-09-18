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
        panel.message = Messages.AppAppModelInstanceTransfers.transferFormats.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPack(url)
    }
    func prepareInstanceImport(_ url: URL) {
        guard !busy else { return }
        perform(Messages.AppAppModelInstanceTransfers.prepareImport(url.lastPathComponent)) { [self] id in
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
        importingInstance = nil; page = .activity
        perform(Messages.AppAppModelInstanceTransfers.finishImport(name)) { [self] id in
            let service = InstanceTransfer(paths: paths)
            do {
                let installer = installer, paths = paths
                let update: @Sendable (InstallProgress) async -> Void = { [weak self] p in await self?.progress(id, p) }
                let instance = try await service.install(prepared, name: name, importJVMArguments: keepJVMArguments, installer: installer, concurrency: state.settings.concurrentDownloads,
                                                         content: { try await CurseForgeService(apiKey: "").materialize(curseFiles, paths: paths, downloader: installer.downloader, manualFiles: manualFiles, progress: update) },
                                                         progress: update)
                if instance.repositoryVersionID != nil { acceptState(try StateStore.load(basePaths)) }
                else { state.instances.append(instance); select(instance) }
                report(Messages.AppAppModelInstanceTransfers.instanceImported(instance.name))
                await service.discard(prepared)
            } catch {
                importingInstance = prepared
                if let failure = error as? RepositoryImportFailure { report(failure.message, level: .error, fileURL: failure.preservedFiles) }
                throw error
            }
        }
    }
    func export(_ instance: GameInstance, to url: URL, format: InstanceExportFormat, includeWorlds: Bool, details: ModpackExportDetails = .init()) {
        guard !isInstanceInUse(instance.id) else { return }
        perform(Messages.AppAppModelInstanceTransfers.exportInstance(instance.name), instanceID: instance.id) { [self] id in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await InstanceTransfer(paths: paths).export(instance, to: url, format: format, includeWorlds: includeWorlds, details: details) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
            report(Messages.AppAppModelInstanceTransfers.instanceExported(instance.name), level: .success, fileURL: url); NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
