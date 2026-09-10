import Foundation

enum ModrinthEndpoints {
    private static let api = URL(string: "https://api.modrinth.com/v2")!
    private static let website = URL(string: "https://modrinth.com")!
    static let versionFiles = api.appending(component: "version_files")

    static func search(_ query: String, type: String, offset: Int, game: String? = nil) throws -> URL {
        var filters = [["project_type:\(type)"]]
        if let game { filters.append(["versions:\(game)"]) }
        let facets = String(decoding: try JSONEncoder().encode(filters), as: UTF8.self)
        return try EndpointURL.build(base: api, path: ["search"], query: [
            .init(name: "query", value: query), .init(name: "facets", value: facets),
            .init(name: "limit", value: "20"), .init(name: "offset", value: String(offset)),
            .init(name: "index", value: query.isEmpty ? "downloads" : "relevance")
        ])
    }
    static func versions(project: String, game: String?, loader: String?) throws -> URL {
        var query: [URLQueryItem] = []
        for (key, value) in [("game_versions", game), ("loaders", loader)] {
            if let value { query.append(.init(name: key, value: String(decoding: try JSONEncoder().encode([value]), as: UTF8.self))) }
        }
        return try EndpointURL.build(base: api, path: ["project", project, "version"], query: query)
    }
    static func version(_ id: String) throws -> URL { try EndpointURL.build(base: api, path: ["version", id]) }
    static func projectPage(type: String, identifier: String) -> URL? {
        guard ["mod", "modpack", "resourcepack", "shader", "datapack", "plugin"].contains(type) else { return nil }
        return try? EndpointURL.build(base: website, path: [type, identifier])
    }
}

extension ModrinthProject {
    public var pageURL: URL? { ModrinthEndpoints.projectPage(type: project_type, identifier: slug) }
}
extension ManagedContent {
    public var modrinthPageURL: URL? { provider == "modrinth" ? ModrinthEndpoints.projectPage(type: kind.rawValue, identifier: projectID) : nil }
}
