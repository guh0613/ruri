import Foundation

enum CurseForgeEndpoints {
    static let api = URL(string: "https://api.curseforge.com/v1")!
    private static let cdn = URL(string: "https://edge.forgecdn.net/files")!
    private static let website = URL(string: "https://www.curseforge.com/minecraft")!
    private static let alternateWebsite = URL(string: "https://curseforge.com/minecraft")!

    enum Route {
        case categories, description(Int), changelog(project: Int, file: Int), search, project(Int), file(project: Int, file: Int), projectFiles(Int), projects, files, fingerprints
        var path: [String] {
            switch self {
            case .categories: ["categories"]
            case .description(let id): ["mods", String(id), "description"]
            case .changelog(let project, let file): ["mods", String(project), "files", String(file), "changelog"]
            case .search: ["mods", "search"]
            case .project(let id): ["mods", String(id)]
            case .file(let project, let file): ["mods", String(project), "files", String(file)]
            case .projectFiles(let id): ["mods", String(id), "files"]
            case .projects: ["mods"]
            case .files: ["mods", "files"]
            case .fingerprints: ["fingerprints", "432"]
            }
        }
    }
    static func request(_ route: Route, query: [URLQueryItem] = []) throws -> URL {
        try EndpointURL.build(base: api, path: route.path, query: query)
    }
    static func allowsAPI(_ url: URL) -> Bool { EndpointURL.belongsTo(url, origin: api) }
    /// Files whose authors opted out of third-party distribution come back with a
    /// null downloadUrl, but they stay on the CDN at a path derived from the file ID
    /// (same approach as HMCL). The caller still verifies the API-provided hash.
    static func cdnFile(id: Int, fileName: String) -> URL? {
        try? EndpointURL.build(base: cdn, path: [String(id / 1000), String(id % 1000), fileName])
    }
    static func filePage(project: CurseForgeProject, fileID: Int) -> URL {
        if let page = project.links?.websiteUrl,
           EndpointURL.belongsTo(page, origin: website) || EndpointURL.belongsTo(page, origin: alternateWebsite),
           var parts = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            parts.query = nil; parts.fragment = nil
            if let base = parts.url, let result = try? EndpointURL.build(base: base, path: ["files", String(fileID)]) { return result }
        }
        let kind = project.contentType == "modpack" ? "modpacks" : project.contentType == "resourcepack" ? "texture-packs" : project.contentType == "shader" ? "shaders" : "mc-mods"
        return (try? EndpointURL.build(base: website, path: [kind, project.slug, "files", String(fileID)])) ?? website
    }
}
