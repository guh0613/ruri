import Foundation
import RuriLocalization

public struct ContentIdentity: Codable, Equatable, Identifiable, Sendable {
    public var id: String { record.provider + ":" + record.projectID }
    public let record: ManagedContent
    public let pageURL: URL?
    public let iconURL: URL?
    public let summary: String?
    public let loaders: [String]
    public let gameVersions: [String]
}

public struct ContentIdentificationResult: Sendable {
    public var matches: [String: [ContentIdentity]] = [:]
    public var failures: [String] = []
}

/// Identifies arbitrary local files without changing their installation records.
/// Cache keys contain the full SHA-512 digest, never a path or a mod name.
public actor ContentIdentificationService {
    private let modrinth: ModrinthService
    private let curseforge: CurseForgeService?
    private let cacheDirectory: URL
    public init(cacheDirectory: URL, modrinth: ModrinthService = ModrinthService(), curseforge: CurseForgeService? = nil) {
        self.cacheDirectory = cacheDirectory.appendingPathComponent("content-identities-v1")
        self.modrinth = modrinth; self.curseforge = curseforge
    }
    private struct Input: Sendable { let file: LocalContentFile; let digest: ContentFileDigest }
    private struct Cached: Codable {
        let checkedAt: Date
        let match: ContentIdentity?
        var fresh: Bool { Date().timeIntervalSince(checkedAt) < (match == nil ? 24 * 3600 : 7 * 24 * 3600) }
    }

    public func identify(_ files: [LocalContentFile], refresh: Bool = false) async throws -> ContentIdentificationResult {
        var result = ContentIdentificationResult(), inputs: [Input] = []
        for file in files {
            try Task.checkCancellation()
            do { inputs.append(Input(file: file, digest: try ContentFileDigest.read(file.url))) }
            catch { if Task.isCancelled { throw CancellationError() }; result.failures.append(error.localizedDescription) }
        }
        for provider in ["modrinth", "curseforge"] {
            if provider == "curseforge", curseforge == nil { continue }
            var pending: [Input] = []
            for input in inputs {
                if !refresh, let data = try? Data(contentsOf: cacheURL(input.digest.sha512, provider: provider)),
                   let cached = try? JSONDecoder().decode(Cached.self, from: data), cached.fresh {
                    if let match = cached.match, match.record.kind == input.file.kind { result.matches[input.file.id, default: []].append(match) }
                } else { pending.append(input) }
            }
            // Both APIs support batching. Keep cancellation boundaries and partial
            // successes when one provider or a later batch is unavailable.
            for start in stride(from: 0, to: pending.count, by: 100) {
                try Task.checkCancellation()
                let batch = Array(pending[start..<min(start + 100, pending.count)])
                do {
                    let found = try await (provider == "modrinth" ? identifyModrinth(batch) : identifyCurseForge(batch))
                    try Task.checkCancellation()
                    for input in batch {
                        let match = found[input.digest.sha512]
                        if let match, match.record.kind == input.file.kind { result.matches[input.file.id, default: []].append(match) }
                        let cached = Cached(checkedAt: Date(), match: match)
                        if let data = try? JSONEncoder().encode(cached) {
                            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                            try? data.write(to: cacheURL(input.digest.sha512, provider: provider), options: .atomic)
                        }
                    }
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    result.failures.append(Messages.ContentDetails.serviceFailure(provider == "modrinth" ? "Modrinth" : "CurseForge", error.localizedDescription).localized)
                    break
                }
            }
        }
        return result
    }
    private func cacheURL(_ hash: String, provider: String) -> URL { cacheDirectory.appendingPathComponent(provider + "-" + hash + ".json") }

    private func identifyModrinth(_ inputs: [Input]) async throws -> [String: ContentIdentity] {
        let versions = try await modrinth.versionsFromHashes(inputs.map { $0.digest.sha512 })
        let projects = try await modrinth.projects(Array(Set(versions.values.map(\.project_id))).sorted())
        let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: ContentIdentity] = [:]
        for input in inputs {
            let digest = input.digest
            guard let version = versions[digest.sha512] else { continue }
            guard let project = byID[version.project_id] else { throw RuriError.message(Messages.ContentDetails.projectUnavailable) }
            guard let kind = ContentKind(rawValue: project.project_type),
                  let file = version.files.first(where: { $0.hashes["sha512"]?.lowercased() == digest.sha512 && $0.size == digest.size }) else { continue }
            let record = ManagedContent(projectID: project.id, versionID: version.id, title: project.title, versionName: version.version_number, publishedAt: version.date_published,
                                        kind: kind, filename: file.filename, sha1: digest.sha1, sha512: digest.sha512, size: digest.size,
                                        requiredProjects: version.dependencies.filter { $0.dependency_type == "required" }.compactMap(\.project_id))
            result[digest.sha512] = ContentIdentity(record: record, pageURL: project.pageURL, iconURL: project.icon_url, summary: project.description, loaders: version.loaders, gameVersions: version.game_versions)
        }
        return result
    }
    private func identifyCurseForge(_ inputs: [Input]) async throws -> [String: ContentIdentity] {
        guard let curseforge else { return [:] }
        let files = try await curseforge.filesFromFingerprints(Array(Set(inputs.map { $0.digest.fingerprint })).sorted())
        let projects = try await curseforge.projects(Array(Set(files.map(\.modId))).sorted())
        let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: ContentIdentity] = [:]
        for input in inputs {
            let digest = input.digest
            // A 32-bit fingerprint can collide. Require the returned file's
            // cryptographic checksum too before offering an update association.
            let exact = files.filter { $0.fileFingerprint == digest.fingerprint && $0.fileLength == digest.size &&
                (($0.sha1 != nil && $0.sha1 == digest.sha1) || ($0.sha1 == nil && $0.md5 == digest.md5)) }
            guard exact.count == 1, let file = exact.first else { continue }
            guard let project = byID[file.modId] else { throw RuriError.message(Messages.ContentDetails.projectUnavailable) }
            guard let rawKind = project.contentType, let kind = ContentKind(rawValue: rawKind) else { continue }
            let record = ManagedContent(provider: "curseforge", projectID: String(project.id), versionID: String(file.id), title: project.name, versionName: file.displayName,
                                        publishedAt: file.fileDate, kind: kind, filename: file.fileName, sha1: digest.sha1, sha512: digest.sha512, md5: digest.md5, size: digest.size,
                                        requiredProjects: file.dependencies.filter { $0.relationType == 3 }.map { String($0.modId) })
            let loaders = file.gameVersions.filter { ["fabric", "quilt", "forge", "neoforge", "liteloader"].contains($0.lowercased()) }
            result[digest.sha512] = ContentIdentity(record: record, pageURL: project.links?.websiteUrl, iconURL: project.logo?.thumbnailUrl, summary: project.summary, loaders: loaders,
                                                   gameVersions: file.gameVersions.filter { !loaders.contains($0) })
        }
        return result
    }
}
