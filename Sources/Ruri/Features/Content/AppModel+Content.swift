import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

extension AppModel {
    func importPack(_ url: URL) {
        guard !busy else { return }
        prepareInstanceImport(url)
    }
    func installContent(project: ModrinthProject, version: ModrinthVersion, instance: GameInstance?) {
        perform(Messages.AppAppModelContent.installContentText1(String(describing: project.title)), instanceID: project.project_type == "modpack" ? nil : instance?.id) { [self] id in
            if project.project_type == "modpack" {
                guard let file = version.primaryFile else { throw RuriError.message(Messages.AppAppModelContent.fileText1) }
                let archive = paths.cache.appendingPathComponent("pack-\(version.id).mrpack")
                progress(id, InstallProgress(Messages.AppAppModelContent.archiveText1))
                try await installer.downloader.fetch(DownloadItem(url: file.url, destination: archive, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
                importingInstance = try await InstanceTransfer(paths: paths).prepare(archive, origin: ModpackOrigin(provider: .modrinth, projectID: project.id, versionID: version.id)) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
                notice = Messages.AppAppModelContent.archiveText2.localized; return
            } else if let instance {
                try await ModrinthService().install(version: version, type: project.project_type, instance: instance, paths: paths, downloader: installer.downloader) { [weak self] p in await self?.progress(id, p) }
            } else { throw RuriError.message(Messages.AppAppModelContent.instanceText1) }
            notice = Messages.AppAppModelContent.instanceText2(String(describing: project.title)).localized
        }
        page = .downloads
    }
}
