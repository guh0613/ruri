import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageCatalog(_ request: CommandRequest) async throws -> Value {
        _ = try await context(request)
        let repository = CatalogRepository(), provider = catalogSource(request), action = request.spec.path.last!
        if action == "categories" { return request.page(try await repository.categories(source: provider).map { .object(["id": .string($0.id), "name": .string($0.name), "type": .string($0.type)]) }) }
        if action == "show" {
            let project = try await repository.project(source: provider, id: request.operand()), detail = try await repository.detail(project)
            return .object(["project": projectValue(project), "description": .string(String(detail.body.prefix(32000))), "descriptionTruncated": .bool(detail.body.count > 32000), "isHTML": .bool(detail.isHTML), "license": .text(detail.license)])
        }
        let start = request.flag("all") ? 0 : request.integer("offset") ?? 0, limit = request.integer("limit") ?? 50
        var offset = start, total = 0, values: [Value] = []
        let project = action == "versions" ? try await repository.project(source: provider, id: request.operand()) : nil
        while true {
            try Task.checkCancellation()
            let page: [Value]
            if let project {
                let response = try await repository.versions(project, game: request.string("game") ?? "", loader: request.string("loader") ?? "", offset: offset)
                total = response.total; page = response.versions.map(versionValue)
            } else {
                var query = CatalogQuery(); query.source = provider; query.type = request.string("type") ?? "mod"; query.text = request.operands.first ?? ""
                query.game = request.string("game") ?? ""; query.loader = request.string("loader") ?? ""; query.category = request.string("category") ?? ""
                query.sort = CatalogSort(rawValue: request.string("sort") ?? "relevance")!; query.offset = offset
                let response = try await repository.search(query); total = response.total; page = response.projects.map(projectValue)
            }
            values += page; offset += page.count
            if page.isEmpty || offset >= total || (!request.flag("all") && values.count >= limit) { break }
        }
        let items = request.flag("all") ? values : Array(values.prefix(limit))
        return .object(["items": .array(items), "total": .integer(total), "offset": .integer(start), "hasMore": .bool(start + items.count < total)])
    }
    @MainActor static func manageContent(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, paths, downloader) = try await context(request), id = try uuid(request.operand())
        let instance = try InstanceService(paths: paths).resolve(id: id), manager = ContentManager(paths: paths, instanceID: id)
        let action = request.spec.path.last!, kind = ContentKind(rawValue: request.string("kind") ?? "mod")!
        if action == "list" { return request.page(try await manager.scan(kind).map(contentValue)) }
        if action == "import" {
            let file = URL(fileURLWithPath: try request.operand(1))
            guard FileManager.default.fileExists(atPath: file.path) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t68a342df34e2.localized) }
            if !request.dryRun {
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
                try await manager.importFiles([file], kind: kind)
            }
            return .object(["dryRun": .bool(request.dryRun), "file": .string(file.path), "kind": .string(kind.rawValue)])
        }
        if action == "install" {
            let repository = CatalogRepository(), project = try await repository.project(source: catalogSource(request), id: request.operand(1))
            let version = try await selectedVersion(project: project, versionID: request.string("version"), instance: instance, repository: repository)
            let planner = CatalogInstallationPlanner(), plan = try await planner.plan(project: project, version: version, instance: instance, paths: paths)
            let manual = try manualFiles(request), missing = plan.manualFiles.filter { manual[$0.id] == nil }
            let result: Value = .object(["dryRun": .bool(request.dryRun), "project": projectValue(project), "version": versionValue(version), "downloadBytes": .integer(plan.downloadSize),
                "files": .array(plan.items.map { .object(["record": managedValue($0.record), "action": .string(String(describing: $0.action))]) }), "manualFiles": .array(missing.map(manualValue))])
            if request.dryRun { return result }
            try requireManualFiles(missing)
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            try await planner.install(plan, paths: paths, downloader: downloader, manualFiles: manual, progress: { output.progress($0) })
            return result
        }
        let files = try await manager.scan(kind), names = Set(strings(request, "file"))
        let check = action == "update-check"
        guard !(request.flag("all") && !names.isEmpty), check || request.flag("all") || !names.isEmpty else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t1474aa1131be.localized) }
        let selected = names.isEmpty ? files : files.filter { names.contains($0.url.lastPathComponent) }
        guard names.isEmpty || Set(selected.map { $0.url.lastPathComponent }) == names else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.tcf02f30209a6.localized) }
        if check || action == "update" {
            let records = selected.compactMap(\.managed), hasCurse = records.contains { $0.provider == "curseforge" }
            let curse = CurseForgeService(apiKey: hasCurse ? try CurseForgeKeyStore.load() : "")
            let checked = try await ContentUpdateChecker(curseforge: hasCurse ? curse : nil).check(records, instance: instance)
            if let issue = checked.failureDescription { throw OperationFailure("UPDATE_CHECK_FAILED", issue, retryable: true) }
            if checked.modrinth.isEmpty && checked.curseforge.isEmpty { return .object(["changed": .bool(false), "updates": .array([])]) }
            let updater = ContentBatchUpdater(curseforge: curse), plan = try await updater.prepare(modrinth: checked.modrinth, curseforge: checked.curseforge, instance: instance, paths: paths)
            let manual = try manualFiles(request), missing = plan.curseforge.filter { $0.requiresManualDownload && manual[$0.id] == nil }
            let result: Value = .object(["dryRun": .bool(request.dryRun || check), "updates": .array(plan.records.map(managedValue)), "downloadBytes": .integer(plan.downloadSize), "manualFiles": .array(missing.map(manualValue))])
            if !check && !request.dryRun {
                try requireManualFiles(missing)
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
                try await updater.install(plan, paths: paths, downloader: downloader, manualFiles: manual, progress: { output.progress($0) })
            }
            return result
        }
        if !request.dryRun {
            let lease = try GameRunLease.acquire(paths: paths, instanceID: id); defer { withExtendedLifetime(lease) {} }
            switch action {
            case "enable": try await manager.setEnabled(true, files: selected)
            case "disable": try await manager.setEnabled(false, files: selected)
            case "remove": _ = try await manager.remove(selected)
            default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t1fb9146947a6.localized)
            }
        }
        return .object(["dryRun": .bool(request.dryRun), "action": .string(action), "files": .array(selected.map(contentValue))])
    }
    static func catalogSource(_ request: CommandRequest) -> CatalogSource { request.string("provider") == "curseforge" ? .curseforge : .modrinth }
    static func projectValue(_ project: CatalogProject) -> Value {
        .object(["id": .string(project.projectID), "provider": .string(project.source == .modrinth ? "modrinth" : "curseforge"), "title": .string(project.title), "type": .string(project.type), "pageURL": .text(project.pageURL?.absoluteString)])
    }
    static func versionValue(_ v: CatalogVersion) -> Value {
        .object(["id": .string(v.id), "name": .string(v.name), "number": .string(v.number), "channel": .string(v.channel), "publishedAt": .string(v.published),
            "gameVersions": .array(v.gameVersions.map(Value.string)), "loaders": .array(v.loaders.map(Value.string)), "filename": .string(v.filename), "bytes": .integer(v.size)])
    }
    static func managedValue(_ v: ManagedContent) -> Value {
        .object(["id": .string(v.id), "provider": .string(v.provider), "projectID": .string(v.projectID), "versionID": .string(v.versionID), "title": .string(v.title), "version": .string(v.versionName), "filename": .string(v.filename), "enabled": .bool(v.enabled), "bytes": .integer(v.size)])
    }
    static func contentValue(_ v: LocalContentFile) -> Value {
        .object(["filename": .string(v.url.lastPathComponent), "title": .string(v.title), "version": .text(v.version), "kind": .string(v.kind.rawValue), "enabled": .bool(v.enabled), "bytes": .integer(v.size), "managed": v.managed.map(managedValue) ?? .null])
    }
    static func manualValue(_ item: PlannedCurseFile) -> Value {
        .object(["fileID": .integer(item.id), "filename": .string(item.file.fileName), "pageURL": .string(item.pageURL.absoluteString), "bytes": .integer(item.file.fileLength), "sha1": .text(item.file.sha1), "md5": .text(item.file.md5)])
    }
    static func strings(_ request: CommandRequest, _ option: String) -> [String] { if case .array(let values) = request.options[option] { values.compactMap(\.string) } else { [] } }
    static func manualFiles(_ request: CommandRequest) throws -> [Int: URL] {
        var result: [Int: URL] = [:]
        for raw in strings(request, "manual") {
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = Int(parts[0]), id > 0, result[id] == nil else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tcf80472afe71.localized) }
            result[id] = URL(fileURLWithPath: parts[1])
        }
        return result
    }
    static func requireManualFiles(_ files: [PlannedCurseFile]) throws {
        guard files.isEmpty else { throw OperationFailure("MANUAL_DOWNLOAD_REQUIRED", Messages.CLIInterface.t22d3a8371f53.localized, details: .object(["files": .array(files.map(manualValue))])) }
    }
    static func selectedVersion(project: CatalogProject, versionID: String?, instance: GameInstance?, repository: CatalogRepository) async throws -> CatalogVersion {
        var offset = 0
        while true {
            let page = try await repository.versions(project, game: instance?.gameVersion ?? "", loader: instance?.loader.modrinthLoader ?? "", offset: offset)
            if let match = page.versions.first(where: { version in versionID.map { version.id == $0 } ?? (version.channel == "release") }) {
                if let instance, !match.supports(instance, type: project.type) { throw OperationFailure("INCOMPATIBLE_VERSION", Messages.CLIInterface.t5c54141389e9.localized) }
                return match
            }
            offset += page.versions.count
            if page.versions.isEmpty || offset >= page.total { break }
        }
        throw OperationFailure("NOT_FOUND", Messages.CLIInterface.t56f6acfec799.localized)
    }
}
