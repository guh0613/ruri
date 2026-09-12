import RuriLocalization
import Foundation
import CryptoKit

extension ModrinthService {
    public func versionsFromHashes(_ hashes: [String], algorithm: String = "sha512") async throws -> [String: ModrinthVersion] {
        guard ["sha1", "sha512"].contains(algorithm), hashes.count <= 100_000 else { throw RuriError.message(Messages.CoreMRPack.versionsFromHashesText1) }
        let length = algorithm == "sha1" ? 40 : 128
        guard hashes.allSatisfy({ $0.range(of: "^[a-fA-F0-9]{\(length)}$", options: .regularExpression) != nil }) else { throw RuriError.message(Messages.CoreMRPack.lengthText1) }
        let unique = Array(Set(hashes.map { $0.lowercased() })).sorted(); var result: [String: ModrinthVersion] = [:]
        for start in stride(from: 0, to: unique.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(unique[start..<min(start + 100, unique.count)])
            var request = URLRequest(url: ModrinthEndpoints.versionFiles); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["hashes": batch, "algorithm": algorithm])
            let versions = try JSONDecoder().decode([String: ModrinthVersion].self, from: await client.data(for: request))
            for (key, value) in versions where batch.contains(key.lowercased()) {
                guard value.files.contains(where: { $0.hashes[algorithm]?.lowercased() == key.lowercased() }) else { throw RuriError.message(Messages.CoreMRPack.versionsText1) }
                result[key.lowercased()] = value
            }
        }
        return result
    }
}

extension InstanceTransfer {
    static let mrpackLoaders: [String: LoaderKind] = ["fabric-loader": .fabric, "quilt-loader": .quilt, "forge": .forge, "neoforge": .neoforge]
    static func describeMRPack(_ root: URL) throws -> InstanceImportDescription {
        let index = try JSONDecoder().decode(ModpackIndex.self, from: read(root.appendingPathComponent("modrinth.index.json")))
        guard index.formatVersion == 1, index.game == "minecraft", let gameVersion = index.dependencies["minecraft"], !index.versionId.isEmpty else { throw RuriError.message(Messages.CoreMRPack.gameVersionText1) }
        let unknown = Set(index.dependencies.keys).subtracting(Set(mrpackLoaders.keys).union(["minecraft"]))
        guard unknown.isEmpty else { throw RuriError.message(Messages.CoreMRPack.unknownText1(String(describing: unknown.sorted().joined(separator: "、")))) }
        let loaders = index.dependencies.keys.filter { mrpackLoaders[$0] != nil }
        guard loaders.count <= 1 else { throw RuriError.message(Messages.CoreMRPack.loadersText1) }
        let instance = GameInstance(name: index.name, gameVersion: gameVersion, loader: loaders.first.flatMap { mrpackLoaders[$0] } ?? .vanilla, loaderVersion: loaders.first.flatMap { index.dependencies[$0] })
        try validate(instance)
        let game = root.appendingPathComponent("overrides")
        guard index.files.count <= 100_000 else { throw RuriError.message(Messages.CoreMRPack.gameText1) }
        var files: [PackFile] = []
        var paths = Set<String>()
        for file in index.files {
            _ = try LauncherPaths.safePath(file.path, within: game)
            guard !file.path.contains(":"), !file.path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." }), paths.insert(file.path.lowercased()).inserted else { throw RuriError.message(Messages.CoreMRPack.pathsText1(String(describing: file.path))) }
            guard let sha1 = file.hashes["sha1"], sha1.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil,
                  let sha512 = file.hashes["sha512"], sha512.range(of: "^[a-fA-F0-9]{128}$", options: .regularExpression) != nil, file.fileSize >= 0 else { throw RuriError.message(Messages.CoreMRPack.sha512Text1(String(describing: file.path))) }
            guard (file.env ?? [:]).values.allSatisfy({ ["required", "optional", "unsupported"].contains($0) }) else { throw RuriError.message(Messages.CoreMRPack.sha512Text2(String(describing: file.path))) }
            if file.env?["client"] == "unsupported" { continue }
            let urls = file.downloads.filter { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil }
            guard let first = urls.first else { throw RuriError.message(Messages.CoreMRPack.firstText1(String(describing: file.path))) }
            files.append(PackFile(path: file.path, sha1: sha1, url: first, sha512: sha512, size: file.fileSize, fallbackURLs: Array(urls.dropFirst()), optional: file.env?["client"] == "optional"))
        }
        var warnings = [Messages.CoreMRPack.warningsText1(String(describing: index.versionId)).localized]
        if let summary = index.summary, !summary.isEmpty { warnings.append(summary) }
        var identities: [String: String] = [:]
        for file in files {
            if let url = file.url, url.host == "cdn.modrinth.com" {
                let parts = url.path.split(separator: "/")
                if parts.count >= 5, parts[0] == "data", parts[2] == "versions" { identities[file.path] = "modrinth:" + parts[1] }
            }
        }
        return InstanceImportDescription(instance: instance, game: game, format: "Modrinth", warnings: warnings, packFiles: files, overlays: [root.appendingPathComponent("client-overrides")], modpack: ModpackDescriptor(version: index.versionId, identities: identities))
    }

    func exportMRPack(_ instance: GameInstance, game: URL, to destination: URL, includeWorlds: Bool, details: ModpackExportDetails,
                      service: ModrinthService = ModrinthService(), progress: @Sendable (InstallProgress) -> Void) async throws {
        guard instance.extraJVMArguments.isEmpty, instance.extraGameArguments?.isEmpty != false, instance.packLibraries?.isEmpty != false, instance.supportedJavaMajors?.isEmpty != false else { throw RuriError.message(Messages.CoreMRPack.exportMRPackText1) }
        guard !details.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, details.version.count <= 128, details.description.count <= 32_768 else { throw RuriError.message(Messages.CoreMRPack.exportMRPackText2) }
        let workspace = paths.cache.appendingPathComponent("export-mrpack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let snapshot = workspace.appendingPathComponent("client-overrides")
        try FileTree.copy(from: game, to: snapshot, excluding: Self.exclusions(game, includeWorlds: includeWorlds)) { done, total in progress(InstallProgress(Messages.CoreMRPack.snapshotText1, completed: done, total: total)) }
        let entries = try FileTree.entries(in: snapshot)
        var hashes: [String: (String, String)] = [:]
        if details.referenceDownloads {
            for entry in entries where !entry.directory && ["mods", "resourcepacks", "shaderpacks"].contains(String(entry.path.split(separator: "/").first ?? "")) && ["jar", "zip"].contains(entry.url.pathExtension.lowercased()) {
                let pair = try Self.packHashes(entry.url); hashes[entry.path] = pair
            }
        }
        var versions: [String: ModrinthVersion] = [:]
        if !hashes.isEmpty {
            progress(InstallProgress(Messages.CoreMRPack.versionsText2, total: hashes.count))
            do { versions = try await service.versionsFromHashes(hashes.values.map { $0.1 }) }
            catch { if Task.isCancelled { throw CancellationError() }; progress(InstallProgress(Messages.CoreMRPack.versionsText3)) }
        }
        var files: [ModpackIndex.File] = []; var referenced = Set<String>()
        let hosts = Set(["cdn.modrinth.com", "github.com", "raw.githubusercontent.com", "gitlab.com"])
        for entry in entries where !entry.directory {
            guard let pair = hashes[entry.path], let version = versions[pair.1], let file = version.files.first(where: { $0.hashes["sha512"]?.lowercased() == pair.1 && $0.hashes["sha1"]?.lowercased() == pair.0 && $0.size == entry.size }),
                  file.url.scheme == "https", hosts.contains(file.url.host ?? ""), file.url.user == nil, file.url.password == nil else { continue }
            files.append(.init(path: entry.path, hashes: ["sha1": pair.0, "sha512": pair.1], env: ["client": "required", "server": "unsupported"], downloads: [file.url], fileSize: entry.size))
            referenced.insert(entry.path)
        }
        var dependencies = ["minecraft": instance.gameVersion]
        if instance.loader != .vanilla {
            guard let key = Self.mrpackLoaders.first(where: { $0.value == instance.loader })?.key, let version = instance.loaderVersion else { throw RuriError.message(Messages.CoreMRPack.versionText1) }
            dependencies[key] = version
        }
        let index = ModpackIndex(formatVersion: 1, game: "minecraft", name: instance.name, versionId: details.version, summary: details.description, dependencies: dependencies, files: files)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SafeArchive.create(from: snapshot, to: destination, prefix: "client-overrides", additionalFiles: ["modrinth.index.json": encoder.encode(index)], excluding: referenced) { done, total in progress(InstallProgress(Messages.CoreMRPack.encoderText1, completed: done, total: total)) }
    }
    static func packHashes(_ url: URL) throws -> (String, String) {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha1 = Insecure.SHA1(); var sha512 = SHA512()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); sha1.update(data: data); sha512.update(data: data) }
        return (sha1.finalize().map { String(format: "%02x", $0) }.joined(), sha512.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
