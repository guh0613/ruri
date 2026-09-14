import Foundation
import Observation

/// Owns navigation state outside the view lifecycle. Failed page requests retain
/// the last successful page, including its range, and can be retried in place.
@MainActor @Observable public final class CatalogBrowser {
    public var query = CatalogQuery()
    public var path: [CatalogProject] = []
    public var preferredInstanceID: UUID?
    public var listLayout = false
    public private(set) var page: CatalogPage?
    public private(set) var displayedQuery: CatalogQuery?
    public private(set) var loading = false
    public private(set) var error: String?
    public var scrollID: String?
    public var recentSearches: [String] = []
    @ObservationIgnored private var cache: [CatalogQuery: CatalogPage] = [:]
    @ObservationIgnored private var cacheOrder: [CatalogQuery] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var collections: [String: (query: CatalogQuery, scrollID: String?)] = [:]
    public init() {}
    public func open(_ project: CatalogProject) {
        if let index = path.firstIndex(where: { $0.id == project.id }) { path = Array(path.prefix(index + 1)) }
        else { path.append(project) }
    }
    public func switchCollection(source: CatalogSource? = nil, type: String? = nil) {
        collections[query.source.rawValue + ":" + query.type] = (query, scrollID)
        let source = source ?? query.source, type = type ?? query.type
        if let saved = collections[source.rawValue + ":" + type] {
            query = saved.query; scrollID = saved.scrollID
        } else {
            var next = CatalogQuery(); next.source = source; next.type = type
            query = next; scrollID = nil
        }
        generation = UUID(); loading = false; error = nil
        page = cache[query.normalized]
        displayedQuery = page == nil ? nil : query.normalized
    }
    public func change(_ update: (inout CatalogQuery) -> Void) {
        var next = query
        update(&next)
        next.offset = 0
        if next.game != query.game || next.loader != query.loader { preferredInstanceID = nil }
        query = next.normalized
        scrollID = nil
    }
    public func rememberSearch() {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recentSearches.removeAll { $0 == text }
        recentSearches.insert(text, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
    }
    public func load(refresh: Bool = false, using search: @Sendable (CatalogQuery) async throws -> CatalogPage) async {
        let requested = query.normalized
        let token = UUID(); generation = token
        error = nil
        if !refresh, let cached = cache[requested] {
            page = cached; displayedQuery = requested; loading = false; return
        }
        loading = true
        defer { if generation == token { loading = false } }
        do {
            // Debounce typing, but make pagination and explicit refresh immediate.
            if !refresh && displayedQuery?.text != requested.text && !requested.text.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
            let result = try await search(requested)
            try Task.checkCancellation()
            guard generation == token, query.normalized == requested else { return }
            cache[requested] = result
            cacheOrder.removeAll { $0 == requested }; cacheOrder.append(requested)
            while cacheOrder.count > 60 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
            page = result; displayedQuery = requested
        } catch {
            guard generation == token, query.normalized == requested, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
        }
    }
}
