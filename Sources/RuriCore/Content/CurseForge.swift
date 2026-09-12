import RuriLocalization
import Foundation
import Security

public enum CurseForgeKeyStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.ruri.launcher.services", kSecAttrAccount as String: "curseforge"] }
    public static func isConfigured() -> Bool {
        var query = query; query[kSecReturnAttributes as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
    public static func load() throws -> String {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw RuriError.message(status == errSecItemNotFound ? Messages.CoreCurseForge.apiKeyMissing : Messages.CoreCurseForge.apiKeyReadFailed(String(describing: status)))
        }
        return key
    }
    public static func save(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw RuriError.message(Messages.CoreCurseForge.invalidApiKey) }
        let value = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(value) { _, new in new }; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw RuriError.message(Messages.CoreCurseForge.apiKeySaveFailed(String(describing: added))) }
        } else if status != errSecSuccess { throw RuriError.message(Messages.CoreCurseForge.apiKeySaveFailed(String(describing: status))) }
    }
    public static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RuriError.message(Messages.CoreCurseForge.apiKeyRemoveFailed(String(describing: status))) }
    }
}

public struct CurseForgeProject: Decodable, Identifiable, Sendable {
    public struct Author: Decodable, Sendable { public let name: String }
    public struct Logo: Decodable, Sendable { public let thumbnailUrl: URL? }
    public struct Links: Decodable, Sendable { public let websiteUrl: URL? }
    public let id: Int
    public let gameId: Int
    public let name: String
    public let slug: String
    public let summary: String
    public let downloadCount: Double
    public let classId: Int?
    public let authors: [Author]?
    public let logo: Logo?
    public let links: Links?
    public let allowModDistribution: Bool?
    public var contentType: String? { switch classId { case 6: "mod"; case 4471: "modpack"; case 12: "resourcepack"; case 6552: "shader"; default: nil } }
    public func page(for fileID: Int) -> URL {
        CurseForgeEndpoints.filePage(project: self, fileID: fileID)
    }
}
public struct CurseForgeFile: Decodable, Identifiable, Sendable {
    public struct Hash: Decodable, Sendable { public let value: String; public let algo: Int }
    public struct Dependency: Decodable, Sendable { public let modId: Int; public let relationType: Int }
    public let id: Int
    public let modId: Int
    public let displayName: String
    public let fileName: String
    public let fileDate: String
    public let fileLength: Int64
    public let releaseType: Int
    public let downloadUrl: String?
    public let gameVersions: [String]
    public let dependencies: [Dependency]
    public let hashes: [Hash]
    public let isAvailable: Bool?
    public var sha1: String? { hash(algorithm: 1, length: 40) }
    public var md5: String? { hash(algorithm: 2, length: 32) }
    public var downloadURL: URL? { downloadUrl.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
    private func hash(algorithm: Int, length: Int) -> String? {
        hashes.first(where: { $0.algo == algorithm && $0.value.range(of: "^[a-fA-F0-9]{\(length)}$", options: .regularExpression) != nil })?.value.lowercased()
    }
    public func downloadItem(to destination: URL, permittedURL: URL?) throws -> DownloadItem {
        try validateDownloadMetadata()
        return DownloadItem(url: permittedURL, destination: destination, sha1: sha1, md5: md5, size: fileLength)
    }
    func validateDownloadMetadata() throws {
        guard id > 0, modId > 0, fileLength >= 0, isAvailable != false, sha1 != nil || md5 != nil else { throw RuriError.message(Messages.CoreCurseForge.invalidDownloadMetadata(fileName)) }
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("\0") else { throw RuriError.message(Messages.CoreCurseForge.invalidFileName) }
    }
    public func supports(_ instance: GameInstance, kind: ContentKind) -> Bool {
        guard gameVersions.contains(instance.gameVersion) else { return false }
        guard kind == .mod else { return true }
        guard instance.loader != .vanilla else { return false }
        let tags = Set(gameVersions.map { $0.lowercased() }).intersection(["fabric", "quilt", "forge", "neoforge", "liteloader"])
        return tags.isEmpty || tags.contains(instance.loader == .legacyfabric ? "fabric" : instance.loader.rawValue)
    }
}
public struct CurseForgePage<Value: Decodable & Sendable>: Decodable, Sendable {
    public struct Pagination: Decodable, Sendable { public let index: Int; public let pageSize: Int; public let resultCount: Int; public let totalCount: Int }
    public let data: [Value]
    public let pagination: Pagination?
}
public struct CurseForgeReference: Codable, Hashable, Sendable {
    public let projectID: Int
    public let fileID: Int
    public let required: Bool?
    public init(projectID: Int, fileID: Int, required: Bool? = nil) { self.projectID = projectID; self.fileID = fileID; self.required = required }
}
public struct PlannedCurseFile: Identifiable, Sendable {
    public var id: Int { file.id }
    public let project: CurseForgeProject
    public let file: CurseForgeFile
    public let kind: ContentKind
    public var downloadURL: URL? { project.allowModDistribution == false ? nil : file.downloadURL }
    public var pageURL: URL { project.page(for: file.id) }
    public var requiresManualDownload: Bool { downloadURL == nil }
    public var record: ManagedContent {
        ManagedContent(provider: "curseforge", projectID: String(project.id), versionID: String(file.id), title: project.name, versionName: file.displayName,
            publishedAt: file.fileDate, kind: kind, filename: file.fileName, sha1: file.sha1, md5: file.md5, size: file.fileLength,
            requiredProjects: kind == .mod ? file.dependencies.filter { $0.relationType == 3 }.map { String($0.modId) } : [])
    }
}
public struct CurseForgeContentPlan: Identifiable, Sendable {
    public let id = UUID()
    public let instance: GameInstance
    public let title: String
    public let files: [PlannedCurseFile]
    public var manualFiles: [PlannedCurseFile] { files.filter(\.requiresManualDownload) }
}
public struct CurseForgeUpdate: Identifiable, Sendable {
    public var id: String { installed.id }
    public let installed: ManagedContent
    public let available: CurseForgeFile
}

private final class CurseForgeRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, CurseForgeEndpoints.allowsAPI(url) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public actor CurseForgeService {
    private let apiKey: String
    private let client: HTTPClient
    private let ownsSession: Bool
    public init(apiKey: String, client: HTTPClient? = nil) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines); self.ownsSession = client == nil
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.timeoutIntervalForRequest = 30
        self.client = client ?? HTTPClient(session: URLSession(configuration: config, delegate: CurseForgeRedirectGuard(), delegateQueue: nil))
    }
    deinit { if ownsSession { client.session.invalidateAndCancel() } }
    public static func cachedFile(_ file: CurseForgeFile, paths: LauncherPaths) async -> URL? {
        guard let url = try? LauncherPaths.safePath("curseforge/\(file.id)/\(file.fileName)", within: paths.cache),
              let check = try? file.downloadItem(to: url, permittedURL: nil), DownloadManager.valid(url, item: check) else { return nil }
        return url
    }
    public static func cacheManualFile(_ source: URL, file: CurseForgeFile, paths: LauncherPaths) async throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              DownloadManager.valid(source, item: try file.downloadItem(to: source, permittedURL: nil)) else { throw RuriError.message(Messages.CoreCurseForge.fileMismatch(String(describing: file.displayName))) }
        let cache = try LauncherPaths.safePath("curseforge/\(file.id)/\(file.fileName)", within: paths.cache)
        if source.standardizedFileURL == cache.standardizedFileURL { return cache }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = cache.deletingLastPathComponent().appendingPathComponent(".manual-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try Task.checkCancellation()
        guard DownloadManager.valid(temporary, item: try file.downloadItem(to: temporary, permittedURL: nil)) else { throw RuriError.message(Messages.CoreCurseForge.packDownloadChanged) }
        guard rename(temporary.path, cache.path) == 0 else { throw RuriError.message(Messages.CoreCurseForge.cacheFileFailed) }
        return cache
    }
    private struct Response<Value: Decodable & Sendable>: Decodable, Sendable { let data: Value }
    private func request<Value: Decodable & Sendable>(_ type: Value.Type, route: CurseForgeEndpoints.Route, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Value {
        guard !apiKey.isEmpty else { throw RuriError.message(Messages.CoreCurseForge.apiKeyRequired) }
        var request = URLRequest(url: try CurseForgeEndpoints.request(route, query: query)); request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try JSONDecoder().decode(type, from: await client.data(for: request))
    }
    public func search(_ query: String, type: String, offset: Int = 0) async throws -> CurseForgePage<CurseForgeProject> {
        let classes = ["mod": 6, "modpack": 4471, "resourcepack": 12, "shader": 6552]
        guard let category = classes[type] else { throw RuriError.message(Messages.CoreCurseForge.unsupportedContentType) }
        return try await request(CurseForgePage<CurseForgeProject>.self, route: .search, query: [
            .init(name: "gameId", value: "432"), .init(name: "classId", value: String(category)), .init(name: "searchFilter", value: query),
            .init(name: "pageSize", value: "20"), .init(name: "index", value: String(max(0, offset))), .init(name: "sortField", value: "6"), .init(name: "sortOrder", value: "desc")])
    }
    public func project(_ id: Int) async throws -> CurseForgeProject {
        guard id > 0 else { throw RuriError.message(Messages.CoreCurseForge.invalidProjectID) }
        let result = try await request(Response<CurseForgeProject>.self, route: .project(id)).data
        guard result.id == id, result.gameId == 432 else { throw RuriError.message(Messages.CoreCurseForge.projectMismatch) }
        return result
    }
    public func file(project id: Int, file fileID: Int) async throws -> CurseForgeFile {
        guard id > 0, fileID > 0 else { throw RuriError.message(Messages.CoreCurseForge.invalidFileID) }
        let result = try await request(Response<CurseForgeFile>.self, route: .file(project: id, file: fileID)).data
        guard result.id == fileID, result.modId == id else { throw RuriError.message(Messages.CoreCurseForge.fileMismatchRequest) }
        return result
    }
    public func files(project id: Int, game: String? = nil, loader: LoaderKind? = nil, offset: Int = 0) async throws -> CurseForgePage<CurseForgeFile> {
        guard id > 0 else { throw RuriError.message(Messages.CoreCurseForge.invalidProjectID) }
        var query: [URLQueryItem] = [.init(name: "pageSize", value: "50"), .init(name: "index", value: String(max(0, offset)))]
        if let game { query.append(.init(name: "gameVersion", value: game)) }
        let loaders: [LoaderKind: Int] = [.forge: 1, .liteloader: 3, .fabric: 4, .legacyfabric: 4, .quilt: 5, .neoforge: 6]
        if let loader, let value = loaders[loader] { query.append(.init(name: "modLoaderType", value: String(value))) }
        let result = try await request(CurseForgePage<CurseForgeFile>.self, route: .projectFiles(id), query: query)
        guard result.data.allSatisfy({ $0.modId == id }) else { throw RuriError.message(Messages.CoreCurseForge.versionListMismatch) }
        return result
    }
    public func resolve(_ references: [CurseForgeReference]) async throws -> [PlannedCurseFile] {
        guard references.count <= 5000, references.allSatisfy({ $0.projectID > 0 && $0.fileID > 0 }) else { throw RuriError.message(Messages.CoreCurseForge.invalidPackFiles) }
        var files: [Int: CurseForgeFile] = [:]; var projects: [Int: CurseForgeProject] = [:]
        let fileIDs = Array(Set(references.map(\.fileID))).sorted(); let projectIDs = Array(Set(references.map(\.projectID))).sorted()
        for start in stride(from: 0, to: fileIDs.count, by: 50) {
            try Task.checkCancellation()
            let body = try JSONEncoder().encode(["fileIds": Array(fileIDs[start..<min(start + 50, fileIDs.count)])])
            for file in try await request(Response<[CurseForgeFile]>.self, route: .files, body: body).data { files[file.id] = file }
        }
        for start in stride(from: 0, to: projectIDs.count, by: 50) {
            try Task.checkCancellation()
            let body = try JSONEncoder().encode(["modIds": Array(projectIDs[start..<min(start + 50, projectIDs.count)])])
            for project in try await request(Response<[CurseForgeProject]>.self, route: .projects, body: body).data { projects[project.id] = project }
        }
        return try references.map { ref in
            guard let file = files[ref.fileID], file.modId == ref.projectID, let project = projects[ref.projectID], project.gameId == 432,
                  let raw = project.contentType, let kind = ContentKind(rawValue: raw) else { throw RuriError.message(Messages.CoreCurseForge.packFileMissing(String(describing: ref.projectID), String(describing: ref.fileID))) }
            try file.validateDownloadMetadata()
            return PlannedCurseFile(project: project, file: file, kind: kind)
        }
    }
    public func plan(file: CurseForgeFile, instance: GameInstance, paths: LauncherPaths) async throws -> CurseForgeContentPlan {
        try await plan(files: [file], instance: instance, paths: paths)
    }
    public func plan(files roots: [CurseForgeFile], instance: GameInstance, paths: LauncherPaths) async throws -> CurseForgeContentPlan {
        var queue = roots; var resolved: [PlannedCurseFile] = []; var seen: [Int: Int] = [:]
        let installed = try await ContentManager(paths: paths, instanceID: instance.id).records()
        while !queue.isEmpty {
            try Task.checkCancellation(); let file = queue.removeFirst()
            if let prior = seen[file.modId] { guard prior == file.id else { throw RuriError.message(Messages.CoreCurseForge.requiredDependencyVersionConflict) }; continue }
            seen[file.modId] = file.id; guard seen.count <= 200 else { throw RuriError.message(Messages.CoreCurseForge.tooManyRequiredDependencies) }
            let project = try await project(file.modId)
            guard let kind = project.contentType.flatMap(ContentKind.init(rawValue:)), file.supports(instance, kind: kind) else { throw RuriError.message(Messages.CoreCurseForge.incompatibleGameOrLoader(String(describing: file.displayName))) }
            _ = try file.downloadItem(to: paths.cache.appendingPathComponent("validation"), permittedURL: nil)
            resolved.append(PlannedCurseFile(project: project, file: file, kind: kind))
            if kind == .mod {
                for dependency in file.dependencies where dependency.relationType == 3 {
                    if seen[dependency.modId] != nil { continue }
                    if let selected = roots.first(where: { $0.modId == dependency.modId }) { queue.append(selected); continue }
                    let options = try await files(project: dependency.modId, game: instance.gameVersion, loader: instance.loader).data.filter { $0.supports(instance, kind: .mod) && $0.isAvailable != false }
                    guard let match = options.first(where: { $0.releaseType == 1 }) ?? options.first else { throw RuriError.message(Messages.CoreCurseForge.missingRequiredDependency(String(describing: dependency.modId))) }
                    queue.append(match)
                }
                for dependency in file.dependencies where dependency.relationType == 5 {
                    guard !installed.contains(where: { $0.provider == "curseforge" && $0.projectID == String(dependency.modId) && $0.enabled }), !seen.keys.contains(dependency.modId) else { throw RuriError.message(Messages.CoreCurseForge.projectDependencyMismatch(project.name, String(describing: dependency.modId))) }
                }
            }
        }
        let ids = Set(resolved.map { $0.project.id })
        guard !resolved.contains(where: { $0.file.dependencies.contains(where: { $0.relationType == 5 && ids.contains($0.modId) }) }) else { throw RuriError.message(Messages.CoreCurseForge.incompatibleDependencies) }
        return CurseForgeContentPlan(instance: instance, title: roots.count == 1 ? (resolved.first?.project.name ?? roots[0].displayName) : Messages.CoreCurseForge.bulkContentUpdate.localized, files: resolved)
    }
    public func install(_ plan: CurseForgeContentPlan, paths: LauncherPaths, downloader: DownloadManager, manualFiles: [Int: URL] = [:], progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let files = try await materialize(plan.files, paths: paths, downloader: downloader, manualFiles: manualFiles, progress: progress)
        try Task.checkCancellation()
        try await ContentManager(paths: paths, instanceID: plan.instance.id).install(files)
    }
    public func materialize(_ items: [PlannedCurseFile], paths: LauncherPaths, downloader: DownloadManager, manualFiles: [Int: URL] = [:], progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> [ContentInstallation] {
        for item in items where item.requiresManualDownload {
            guard let file = manualFiles[item.id] else { throw RuriError.message(Messages.CoreCurseForge.manualDownloadRequired(item.file.fileName)) }
            let check = try item.file.downloadItem(to: file, permittedURL: nil)
            guard DownloadManager.valid(file, item: check) else { throw RuriError.message(Messages.CoreCurseForge.checksumMismatch(String(describing: item.file.displayName))) }
        }
        var installations: [ContentInstallation] = []
        for item in items {
            try Task.checkCancellation()
            let cache = try LauncherPaths.safePath("curseforge/\(item.id)/\(item.file.fileName)", within: paths.cache)
            await progress(InstallProgress(Messages.CoreCurseForge.downloadFile(item.project.name), completed: installations.count, total: items.count))
            if let file = manualFiles[item.id] {
                let check = try item.file.downloadItem(to: file, permittedURL: nil)
                guard DownloadManager.valid(file, item: check) else { throw RuriError.message(Messages.CoreCurseForge.fileChecksumFailed(item.file.fileName)) }
                installations.append(ContentInstallation(record: item.record, source: file))
            } else {
                try await downloader.fetch(item.file.downloadItem(to: cache, permittedURL: item.downloadURL))
                installations.append(ContentInstallation(record: item.record, source: cache))
            }
        }
        return installations
    }
    public func updates(for records: [ManagedContent], instance: GameInstance) async throws -> [CurseForgeUpdate] {
        var result: [CurseForgeUpdate] = []
        for record in records where record.provider == "curseforge" {
            try Task.checkCancellation()
            guard let projectID = Int(record.projectID), let fileID = Int(record.versionID) else { continue }
            let available = try await files(project: projectID, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader : nil).data
            guard let next = available.first(where: { $0.releaseType == 1 && $0.supports(instance, kind: record.kind) }), next.id != fileID else { continue }
            let date: String
            if let published = record.publishedAt { date = published } else { date = try await file(project: projectID, file: fileID).fileDate }
            if Self.date(next.fileDate) > Self.date(date) { result.append(CurseForgeUpdate(installed: record, available: next)) }
        }
        return result
    }
    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: value) ?? .distantPast
    }
}
