import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func managePack(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        var (state, paths, downloader) = try await context(request)
        let action = request.spec.path.last!, manual = try manualFiles(request)
        let importing = action == "import" || action == "install"
        if importing {
            let directory = try directoryID(request.required("directory"))
            guard directory == GameDirectory.defaultID || state.gameDirectories?.contains(where: { $0.id == directory }) == true else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t4c0ebc2810f1.localized) }
            state.selectedDirectoryID = directory
            paths = basePaths(request).configured(with: state)
        }
        let transfer = InstanceTransfer(paths: paths), releases = ModpackReleaseService()
        var instance: GameInstance?, pack: InstalledModpack?
        if !importing {
            let id = try uuid(request.operand()); instance = try InstanceService(paths: paths).resolve(id: id)
            guard let saved = try ModpackRegistry.load(paths: paths, instanceID: id) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.te28b99d2f4f4.localized) }; pack = saved
            if action == "show" { return packValue(saved, instanceID: id) }
            if action == "rollback" {
                let available = ModpackUpdateStore.hasBackup(paths: paths, instanceID: id)
                guard available else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.tf47c36a30379.localized) }
                if request.dryRun { return .object(["dryRun": .bool(true), "instanceID": .string(id.uuidString), "available": .bool(true)]) }
                let result = try await ModpackUpdater(paths: paths, downloader: downloader).rollback(instance!)
                return .object(["instanceID": .string(id.uuidString), "preservedFiles": .integer(result.preservedFiles)])
            }
            if action == "update-check" {
                let key = saved.origin?.provider == .curseforge ? try CurseForgeKeyStore.load() : ""
                let limit = request.integer("limit") ?? 50, start = request.integer("offset") ?? 0
                var offset = start, items: [ModpackRelease] = [], more = false
                repeat {
                    let response = try await releases.versions(for: saved, curseForgeKey: key, offset: offset)
                    // Modrinth's API returns the complete version list.
                    let page = saved.origin?.provider == .modrinth ? Array(response.items.dropFirst(start)) : response.items
                    items += page; more = response.nextOffset != nil
                    guard let next = response.nextOffset, request.flag("all") || items.count < limit else { break }; offset = next
                } while true
                return .object(["current": packValue(saved, instanceID: id), "releases": .array((request.flag("all") ? items : Array(items.prefix(limit))).map(releaseValue)), "offset": .integer(start), "hasMore": .bool(more || (!request.flag("all") && items.count > limit))])
            }
        }
        if request.flag("replace") && !request.dryRun && !request.flag("yes") { throw OperationFailure("CONFIRMATION_REQUIRED", Messages.CLIInterface.tc94ca55edbe4.localized) }
        let prepared: PreparedInstanceImport
        if action == "import" { prepared = try await transfer.prepare(URL(fileURLWithPath: request.operand())) }
        else if let file = request.string("file") {
            guard request.string("version") == nil, request.string("archive") == nil else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t886cba0bd15a.localized) }
            prepared = try await transfer.prepare(URL(fileURLWithPath: file))
        } else {
            let release: ModpackRelease
            if action == "install" {
                let repository = CatalogRepository(), project = try await repository.project(source: catalogSource(request), id: request.operand())
                let version = try await selectedVersion(project: project, versionID: request.string("version"), instance: nil, repository: repository)
                release = try ModpackReleaseService.release(project: project, version: version)
            } else {
                let version = try request.required("version"), saved = pack!
                let key = saved.origin?.provider == .curseforge ? try CurseForgeKeyStore.load() : ""
                var offset = 0, selected: ModpackRelease?
                repeat {
                    let response = try await releases.versions(for: saved, curseForgeKey: key, offset: offset)
                    selected = response.items.first { $0.id == version }
                    guard selected == nil, let next = response.nextOffset else { break }; offset = next
                } while true
                guard let selected else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t092095eba967.localized) }; release = selected
            }
            if release.requiresManualDownload && request.string("archive") == nil { throw OperationFailure("MANUAL_DOWNLOAD_REQUIRED", Messages.CLIInterface.t75d07f6960ff.localized, details: releaseValue(release)) }
            prepared = try await releases.prepare(release, manualFile: request.string("archive").map { URL(fileURLWithPath: $0) }, paths: paths, downloader: downloader, progress: { output.progress($0) })
        }
        var update: PreparedModpackUpdate?
        let updater = ModpackUpdater(paths: paths, downloader: downloader)
        do {
            let curse = CurseForgeService(apiKey: prepared.curseForgeFiles.isEmpty ? "" : try CurseForgeKeyStore.load())
            let files = prepared.curseForgeFiles.isEmpty ? [] : try await curse.resolve(prepared.curseForgeFiles)
            let missing = files.filter { $0.requiresManualDownload && manual[$0.id] == nil }
            var result: [String: Value] = ["dryRun": .bool(request.dryRun), "format": .string(prepared.format), "name": .string(prepared.instance.name),
                "gameVersion": .string(prepared.instance.gameVersion), "files": .integer(prepared.fileCount), "bytes": .integer(prepared.byteCount), "manualFiles": .array(missing.map(manualValue)),
                "warnings": .array(prepared.warnings.map(Value.string))]
            if importing {
                let name = try request.required("name")
                try await transfer.validateDestination(prepared, name: name)
                if !request.dryRun {
                    try requireManualFiles(missing)
                    let imported = try await transfer.install(prepared, name: name, importJVMArguments: request.flag("import-jvm-arguments"), installer: GameInstaller(paths: paths, downloader: downloader), concurrency: state.settings.concurrentDownloads,
                        content: { [paths, downloader] in try await curse.materialize(files, paths: paths, downloader: downloader, manualFiles: manual, progress: { output.progress($0) }) }, progress: { output.progress($0) })
                    if imported.repositoryVersionID == nil {
                        try StateStore.updateIfChanged(paths) { state in state.instances.append(imported) }
                    }
                    result["instance"] = instanceValue(imported, paths: paths.including(imported))
                }
            } else {
                if request.dryRun && !missing.isEmpty { result["complete"] = .bool(false) }
                else {
                    try requireManualFiles(missing)
                    let content = try await curse.materialize(files, paths: paths, downloader: downloader, manualFiles: manual, progress: { output.progress($0) })
                    let plan = try await updater.prepare(prepared, for: instance!, keepJVMArguments: request.flag("import-jvm-arguments"), content: content, concurrency: state.settings.concurrentDownloads, progress: { output.progress($0) })
                    update = plan
                    result["changes"] = .array(plan.changes.map { .object(["path": .string($0.id), "action": .string($0.action.rawValue), "conflict": .bool($0.conflict), "explanation": .text($0.explanation)]) })
                    if !request.dryRun {
                        let keeping = request.flag("replace") ? Set<String>() : Set(plan.changes.filter { $0.action == .keep }.map(\.id))
                        _ = try await updater.apply(plan, keepingLocal: keeping, concurrency: state.settings.concurrentDownloads, progress: { output.progress($0) })
                    }
                }
            }
            if let update { await updater.discard(update) }; await transfer.discard(prepared)
            return .object(result)
        } catch {
            if let update { await updater.discard(update) }; await transfer.discard(prepared); throw error
        }
    }
    static func packValue(_ pack: InstalledModpack, instanceID: UUID) -> Value {
        .object(["instanceID": .string(instanceID.uuidString), "name": .string(pack.name), "version": .string(pack.version), "format": .string(pack.format),
                 "provider": .text(pack.origin?.provider.rawValue), "projectID": .text(pack.origin?.projectID), "versionID": .text(pack.origin?.versionID), "managedFiles": .integer(pack.files.count)])
    }
    static func releaseValue(_ release: ModpackRelease) -> Value {
        .object(["id": .string(release.id), "title": .string(release.title), "gameVersions": .array(release.gameVersions.map(Value.string)), "publishedAt": .text(release.publishedAt), "stable": .bool(release.stable), "manualDownloadRequired": .bool(release.requiresManualDownload), "pageURL": .text(release.page?.absoluteString)])
    }
    @MainActor static func fetch(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, _, downloader) = try await context(request)
        guard let url = URL(string: try request.operand()), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              let size = request.integer("size"), size >= 0, let sha1 = request.string("sha1"), sha1.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tca976a5cf5f9.localized) }
        let file = URL(fileURLWithPath: try request.operand(1)), item = DownloadItem(url: url, destination: file, sha1: sha1, size: Int64(size))
        if !request.dryRun {
            if FileManager.default.fileExists(atPath: file.path), !DownloadManager.valid(file, item: item) { throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.tb634c8d3959d.localized) }
            try await downloader.fetch(item) { output.event("progress", .object(["receivedBytes": .integer($0.receivedBytes), "totalBytes": .integer($0.totalBytes ?? Int64(size))])) }
        }
        return .object(["file": .string(file.path), "dryRun": .bool(request.dryRun), "verified": .bool(!request.dryRun)])
    }
}
