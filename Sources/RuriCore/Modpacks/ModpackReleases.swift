import RuriLocalization
import Foundation

public struct ModpackRelease: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let gameVersions: [String]
    public let publishedAt: String?
    public let stable: Bool
    public let page: URL?
    public let requiresManualDownload: Bool
    let origin: ModpackOrigin
    let filename: String
    let url: URL?
    let sha1: String?
    let sha512: String?
    let md5: String?
    let size: Int64
}
public struct ModpackReleases: Sendable {
    public let items: [ModpackRelease]
    public let nextOffset: Int?
}

public actor ModpackReleaseService {
    public init() {}
    public static func release(project: CatalogProject, version: CatalogVersion) throws -> ModpackRelease {
        guard project.type == "modpack" else { throw RuriError.message(Messages.CoreModpackReleases.projectIsNotModpack) }
        switch (project, version) {
        case (.modrinth(let project), .modrinth(let version)) where version.project_id == project.id:
            let archives = version.files.filter { $0.filename.lowercased().hasSuffix(".mrpack") }
            guard let file = archives.first(where: \.primary) ?? archives.first else { throw RuriError.message(Messages.CoreModpackReleases.missingReleaseChecksum) }
            return .init(id: version.id, title: version.name, gameVersions: version.game_versions, publishedAt: version.date_published,
                stable: version.version_type == nil || version.version_type == "release", page: project.pageURL, requiresManualDownload: false,
                origin: .init(provider: .modrinth, projectID: project.id, versionID: version.id), filename: file.filename, url: file.url,
                sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], md5: nil, size: file.size)
        case (.curseforge(let project), .curseforge(let file)) where file.modId == project.id:
            return .init(id: String(file.id), title: file.displayName, gameVersions: file.gameVersions, publishedAt: file.fileDate, stable: file.releaseType == 1,
                page: project.page(for: file.id), requiresManualDownload: file.downloadURL == nil, origin: .init(provider: .curseforge, projectID: String(project.id), versionID: String(file.id)),
                filename: file.fileName, url: file.downloadURL, sha1: file.sha1, sha512: nil, md5: file.md5, size: file.fileLength)
        default: throw RuriError.message(Messages.Discovery.versionProjectMismatch)
        }
    }
    public func versions(for pack: InstalledModpack, curseForgeKey: String = "", offset: Int = 0) async throws -> ModpackReleases {
        guard let origin = pack.origin, let projectID = origin.projectID else { return .init(items: [], nextOffset: nil) }
        switch origin.provider {
        case .modrinth:
            let versions = try await ModrinthService().versions(project: projectID)
            let items = versions.compactMap { version -> ModpackRelease? in
                let archives = version.files.filter { $0.filename.lowercased().hasSuffix(".mrpack") }
                guard version.project_id == projectID, let file = archives.first(where: \.primary) ?? archives.first else { return nil }
                return .init(id: version.id, title: version.name, gameVersions: version.game_versions, publishedAt: version.date_published,
                             stable: version.version_type == nil || version.version_type == "release", page: nil, requiresManualDownload: false,
                             origin: .init(provider: .modrinth, projectID: projectID, versionID: version.id), filename: file.filename,
                             url: file.url, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], md5: nil, size: file.size)
            }
            return .init(items: items, nextOffset: nil)
        case .curseforge:
            guard let projectID = Int(projectID) else { throw RuriError.message(Messages.CoreModpackReleases.invalidPackProjectID) }
            let service = CurseForgeService(apiKey: curseForgeKey), project = try await service.project(projectID)
            guard project.contentType == "modpack" else { throw RuriError.message(Messages.CoreModpackReleases.projectIsNotModpack) }
            let page = try await service.files(project: projectID, offset: offset)
            let items = page.data.filter { $0.isAvailable != false }.map { file in
                ModpackRelease(id: String(file.id), title: file.displayName, gameVersions: file.gameVersions, publishedAt: file.fileDate,
                               stable: file.releaseType == 1, page: project.page(for: file.id), requiresManualDownload: file.downloadURL == nil,
                               origin: .init(provider: .curseforge, projectID: String(projectID), versionID: String(file.id)), filename: file.fileName,
                               url: file.downloadURL, sha1: file.sha1, sha512: nil, md5: file.md5, size: file.fileLength)
            }
            let next = offset + page.data.count
            return .init(items: items, nextOffset: next < (page.pagination?.totalCount ?? next) && !page.data.isEmpty ? next : nil)
        case .mcbbs: return .init(items: [], nextOffset: nil)
        }
    }
    public func prepare(_ release: ModpackRelease, manualFile: URL? = nil, paths: LauncherPaths, downloader: DownloadManager,
                        progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> PreparedInstanceImport {
        guard release.sha1 != nil || release.sha512 != nil || release.md5 != nil else { throw RuriError.message(Messages.CoreModpackReleases.missingReleaseChecksum) }
        let archive = try manualFile ?? LauncherPaths.safePath("pack-updates/\(release.origin.provider.rawValue)/\(release.id)/\(release.filename)", within: paths.cache)
        let item = DownloadItem(url: release.url, destination: archive, sha1: release.sha1, sha512: release.sha512, md5: release.md5, size: release.size)
        if manualFile == nil {
            guard !release.requiresManualDownload, release.url != nil else { throw RuriError.message(Messages.CoreModpackReleases.curseForgeDownloadRequired) }
            await progress(InstallProgress(Messages.CoreModpackReleases.downloadingPackRelease))
            try await downloader.fetch(item)
        }
        guard DownloadManager.valid(archive, item: item) else { throw RuriError.message(Messages.CoreModpackReleases.selectedReleaseMismatch) }
        return try await InstanceTransfer(paths: paths).prepare(archive, origin: release.origin)
    }
}
