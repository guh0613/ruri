import Foundation
import RuriLocalization

/// A session-scoped catalog cache. Returning to a page is instant; refresh is explicit.
public actor CatalogRepository {
    private let modrinth: ModrinthService
    private let curseForge: @Sendable () throws -> CurseForgeService
    private var details: [String: CatalogDetail] = [:]
    private var projects: [String: CatalogProject] = [:]
    private var versionPages: [String: CatalogVersionPage] = [:]
    private var modrinthVersions: [String: [ModrinthVersion]] = [:]
    private var categoryLists: [CatalogSource: [CatalogCategory]] = [:]
    public init(modrinth: ModrinthService = ModrinthService(), curseForge: @escaping @Sendable () throws -> CurseForgeService = { try CurseForgeService(apiKey: CurseForgeKeyStore.load()) }) {
        self.modrinth = modrinth; self.curseForge = curseForge
    }
    public func search(_ input: CatalogQuery) async throws -> CatalogPage {
        let q = input.normalized
        if q.source == .modrinth {
            let page = try await modrinth.search(q.text, type: q.type, offset: q.offset, game: q.game.isEmpty ? nil : q.game, loader: q.loader.isEmpty ? nil : q.loader, category: q.category.isEmpty ? nil : q.category, sort: q.sort)
            return CatalogPage(projects: page.hits.map(CatalogProject.modrinth), total: page.total_hits)
        }
        let page = try await curseForge().search(q.text, type: q.type, offset: q.offset, game: q.game, loader: q.loader, category: q.category, sort: q.sort)
        return CatalogPage(projects: page.data.map(CatalogProject.curseforge), total: min(page.pagination?.totalCount ?? page.data.count, 10_000))
    }
    public func categories(source: CatalogSource) async throws -> [CatalogCategory] {
        if let cached = categoryLists[source] { return cached }
        let result: [CatalogCategory]
        if source == .modrinth {
            result = try await modrinth.categories().map { CatalogCategory(id: $0.name, name: $0.name, type: $0.project_type) }
        } else {
            result = try await curseForge().categories().compactMap { c in
                guard let type = [6: "mod", 4471: "modpack", 12: "resourcepack", 6552: "shader"][c.classId ?? c.parentCategoryId ?? 0] else { return nil }
                return CatalogCategory(id: String(c.id), name: c.name, type: type)
            }
        }
        categoryLists[source] = result
        return result
    }
    public func project(source: CatalogSource, id: String) async throws -> CatalogProject {
        let key = source.rawValue + ":" + id
        if let cached = details[key] { return cached.project }
        if let cached = projects[key] { return cached }
        let result: CatalogProject
        switch source {
        case .modrinth: result = .modrinth(try await modrinth.project(id))
        case .curseforge:
            guard let id = Int(id), id > 0 else { throw RuriError.message(Messages.CoreCurseForge.invalidProjectID) }
            result = .curseforge(try await curseForge().project(id))
        }
        try Task.checkCancellation()
        if projects.count >= 100 { projects.removeAll(keepingCapacity: true) }
        projects[key] = result
        return result
    }
    public func dependency(_ dependency: CatalogDependency) async throws -> CatalogProject {
        if let id = dependency.projectID { return try await project(source: dependency.source, id: id) }
        if dependency.source == .modrinth, let id = dependency.versionID {
            let version = try await modrinth.version(id)
            return .modrinth(try await modrinth.project(version.project_id))
        }
        throw RuriError.message(Messages.CoreModrinthContentPlan.missingDependencyDownloadID)
    }
    public func detail(_ project: CatalogProject, refresh: Bool = false) async throws -> CatalogDetail {
        if !refresh, let cached = details[project.id] { return cached }
        let result: CatalogDetail
        switch project {
        case .modrinth(let hit):
            let p = try await modrinth.project(hit.id)
            let links = [(Messages.Discovery.sourceCode.localized, "chevron.left.forwardslash.chevron.right", p.source_url), (Messages.Discovery.issues.localized, "ladybug", p.issues_url), (Messages.Discovery.wiki.localized, "book", p.wiki_url), ("Discord", "bubble.left.and.bubble.right", p.discord_url)].compactMap { title, symbol, url in url.map { CatalogLink(title: title, symbol: symbol, url: $0) } }
            result = CatalogDetail(project: .modrinth(p), body: p.body ?? p.description, isHTML: false, gallery: p.gallery.map { CatalogGalleryImage(url: $0.url, title: $0.title) }, links: links, license: p.license?.name ?? p.license?.id)
        case .curseforge(let hit):
            let service = try curseForge()
            async let project = service.project(hit.id)
            async let body = service.description(project: hit.id)
            let p = try await project
            let links = [(Messages.Discovery.sourceCode.localized, "chevron.left.forwardslash.chevron.right", p.links?.sourceUrl), (Messages.Discovery.issues.localized, "ladybug", p.links?.issuesUrl), (Messages.Discovery.wiki.localized, "book", p.links?.wikiUrl)].compactMap { title, symbol, url in url.map { CatalogLink(title: title, symbol: symbol, url: $0) } }
            result = try await CatalogDetail(project: .curseforge(p), body: body, isHTML: true, gallery: p.screenshots?.map { CatalogGalleryImage(url: $0.url, title: $0.title) } ?? [], links: links, license: nil)
        }
        try Task.checkCancellation()
        if details.count >= 40 { details.removeAll(keepingCapacity: true) }
        details[project.id] = result
        return result
    }
    public func versions(_ project: CatalogProject, game: String = "", loader: String = "", offset: Int = 0, refresh: Bool = false) async throws -> CatalogVersionPage {
        let key = [project.id, game, loader].joined(separator: "|")
        let pageKey = key + "|\(offset)"
        if !refresh, let cached = versionPages[pageKey] { return cached }
        let result: CatalogVersionPage
        switch project {
        case .modrinth(let p):
            let all: [ModrinthVersion]
            if !refresh, let cached = modrinthVersions[key] { all = cached }
            else {
                all = try await modrinth.versions(project: p.id, game: game.isEmpty ? nil : game, loader: loader.isEmpty ? nil : loader).sorted { ($0.date_published ?? "") > ($1.date_published ?? "") }
                if modrinthVersions.count >= 30 { modrinthVersions.removeAll(keepingCapacity: true) }
                modrinthVersions[key] = all
            }
            result = CatalogVersionPage(versions: Array(all.dropFirst(max(0, offset)).prefix(50)).map(CatalogVersion.modrinth), total: all.count)
        case .curseforge(let p):
            let kind = LoaderKind.allCases.first { $0.modrinthLoader == loader }
            let page = try await curseForge().files(project: p.id, game: game.isEmpty ? nil : game, loader: kind, offset: offset)
            result = CatalogVersionPage(versions: page.data.map(CatalogVersion.curseforge), total: min(page.pagination?.totalCount ?? page.data.count, 10_000))
        }
        try Task.checkCancellation()
        if refresh { versionPages = versionPages.filter { !$0.key.hasPrefix(key + "|") } }
        if versionPages.count >= 80 { versionPages.removeAll(keepingCapacity: true) }
        versionPages[pageKey] = result
        return result
    }
    public func changelog(_ version: CatalogVersion) async throws -> String {
        switch version {
        case .modrinth(let v): return v.changelog ?? ""
        case .curseforge(let f): return try await curseForge().changelog(project: f.modId, file: f.id)
        }
    }
}
