import Foundation

enum CurseForgeEndpoints {
    static let api = URL(string: "https://api.curseforge.com/v1")!
    private static let website = URL(string: "https://www.curseforge.com/minecraft")!
    private static let alternateWebsite = URL(string: "https://curseforge.com/minecraft")!

    enum Route {
        case search, project(Int), file(project: Int, file: Int), projectFiles(Int), projects, files
        var path: [String] {
            switch self {
            case .search: ["mods", "search"]
            case .project(let id): ["mods", String(id)]
            case .file(let project, let file): ["mods", String(project), "files", String(file)]
            case .projectFiles(let id): ["mods", String(id), "files"]
            case .projects: ["mods"]
            case .files: ["mods", "files"]
            }
        }
    }
    static func request(_ route: Route, query: [URLQueryItem] = []) throws -> URL {
        try EndpointURL.build(base: api, path: route.path, query: query)
    }
    static func allowsAPI(_ url: URL) -> Bool { EndpointURL.belongsTo(url, origin: api) }
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
