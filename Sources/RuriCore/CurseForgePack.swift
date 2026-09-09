import Foundation

struct CurseForgeManifest: Decodable {
    struct Minecraft: Decodable {
        struct Loader: Decodable { let id: String; let primary: Bool? }
        let version: String
        let modLoaders: [Loader]
    }
    let manifestType: String
    let manifestVersion: Int
    let name: String
    let version: String?
    let author: String?
    let minecraft: Minecraft
    let files: [CurseForgeReference]
    let overrides: String?
}

extension InstanceTransfer {
    static func describeCurseForge(_ root: URL) throws -> InstanceImportDescription {
        let manifest = try JSONDecoder().decode(CurseForgeManifest.self, from: read(root.appendingPathComponent("manifest.json")))
        guard manifest.manifestType == "minecraftModpack", manifest.manifestVersion == 1 else { throw RuriError.message("不支持的 CurseForge 整合包格式") }
        guard manifest.minecraft.modLoaders.count <= 1 else { throw RuriError.message("此整合包包含多个加载器，暂时无法安装。") }
        var loader = LoaderKind.vanilla; var version: String?
        if let entry = manifest.minecraft.modLoaders.first {
            guard let dash = entry.id.firstIndex(of: "-"), let kind = LoaderKind(rawValue: String(entry.id[..<dash])), kind != .vanilla else { throw RuriError.message("尚未支持的整合包加载器：\(entry.id)") }
            loader = kind; version = String(entry.id[entry.id.index(after: dash)...])
        }
        let instance = GameInstance(name: manifest.name, gameVersion: manifest.minecraft.version, loader: loader, loaderVersion: version)
        try validate(instance)
        guard manifest.files.count <= 5000, manifest.files.allSatisfy({ $0.projectID > 0 && $0.fileID > 0 }),
              Set(manifest.files.map(\.projectID)).count == manifest.files.count else { throw RuriError.message("整合包包含重复项目或无效文件标识") }
        let game = try LauncherPaths.safePath(manifest.overrides ?? "overrides", within: root)
        if FileManager.default.fileExists(atPath: game.path) {
            let info = try game.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw RuriError.message("整合包 overrides 必须是实际目录") }
        }
        var warnings: [String] = []
        if !manifest.files.isEmpty { warnings.append("需要下载 \(manifest.files.count) 个 CurseForge 文件。下一步可查看可选内容，并补齐需要手动下载的文件。") }
        if let author = manifest.author, !author.isEmpty { warnings.append("整合包作者：\(author)") }
        return InstanceImportDescription(instance: instance, game: game, format: "CurseForge", warnings: warnings, curseForgeFiles: manifest.files, modpack: ModpackDescriptor(version: manifest.version ?? ""))
    }

    static func validatePackContent(_ content: [ContentInstallation], references: [CurseForgeReference]) throws {
        let expected = Set(references.map { "\($0.projectID):\($0.fileID)" })
        let required = Set(references.filter { $0.required != false }.map { "\($0.projectID):\($0.fileID)" })
        let actual = Set(content.map { "\($0.record.projectID):\($0.record.versionID)" })
        guard required.isSubset(of: actual), actual.isSubset(of: expected), content.allSatisfy({ $0.record.provider == "curseforge" }),
              actual.count == content.count, Set(content.map { $0.record.relativePath.lowercased() }).count == content.count else { throw RuriError.message("请先解析并下载整合包清单中的 CurseForge 文件。") }
        for item in content {
            let record = item.record
            guard !record.filename.contains("/"), !record.filename.contains("\\"), URL(fileURLWithPath: record.filename).pathExtension.lowercased() == record.kind.fileExtension,
                  record.sha1 != nil || record.md5 != nil,
                  DownloadManager.valid(item.source, item: DownloadItem(url: nil, destination: item.source, sha1: record.sha1, md5: record.md5, size: record.size)) else { throw RuriError.message("整合包文件校验失败：\(record.filename)") }
        }
    }

    // A pack is installed into a fresh directory. Its bundled overrides are
    // authoritative; changed overrides remain local files instead of acquiring
    // misleading version metadata from the catalog download.
    static func copyPackContent(_ content: [ContentInstallation], to paths: LauncherPaths, instanceID: UUID) throws {
        guard !content.isEmpty else { return }
        var records: [ManagedContent] = []
        for item in content {
            try Task.checkCancellation()
            let target = try LauncherPaths.safePath(item.record.relativePath, within: paths.game(instanceID))
            if FileManager.default.fileExists(atPath: target.path) {
                let check = DownloadItem(url: nil, destination: target, sha1: item.record.sha1, md5: item.record.md5, size: item.record.size)
                if DownloadManager.valid(target, item: check) { records.append(item.record) }
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: item.source, to: target); records.append(item.record)
            }
        }
        let projectIDs = Set(records.map(\.projectID))
        for i in records.indices { records[i].requiredProjects = records[i].requiredProjects.filter { projectIDs.contains($0) } }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: paths.gameDataState(instanceID), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: paths.gameDataState(instanceID).appendingPathComponent("content.json"), options: .atomic)
    }
}
