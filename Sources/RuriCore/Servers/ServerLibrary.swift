import Foundation
import RuriLocalization

public struct ServerPreference: Codable, Equatable, Identifiable, Sendable {
    public var id: String { address.key }
    public let address: ServerAddress
    public var favorite: Bool
    public var alias: String
    public var notes: String
    public var preferredInstanceID: UUID?
    public init(address: ServerAddress, favorite: Bool = false, alias: String = "", notes: String = "", preferredInstanceID: UUID? = nil) {
        self.address = address; self.favorite = favorite; self.alias = alias; self.notes = notes; self.preferredInstanceID = preferredInstanceID
    }
    func validate() throws {
        guard alias.utf8.count <= 1024, notes.utf8.count <= 16384 else { throw RuriError.message(Messages.Servers.invalidList) }
    }
}

public struct ServerLibraryItem: Identifiable, Sendable {
    public var id: String { address.key }
    public let address: ServerAddress
    public var name: String
    public var preference: ServerPreference?
    public var instanceIDs: [UUID]
    public var icon: Data?
    public var playedInstanceIDs: [UUID] = []
}

public struct ServerLibrarySnapshot: Sendable {
    public var items: [ServerLibraryItem]
    public var lists: [UUID: ServerListSnapshot]
    public var errors: [UUID: String]
    public var history: [String: ServerPlaySummary]
    public var historyError: String?
}

public enum ServerLibrary {
    public static func load(paths: LauncherPaths, state: PersistentState) -> ServerLibrarySnapshot {
        let paths = paths.configured(with: state)
        var items: [String: ServerLibraryItem] = [:], lists: [UUID: ServerListSnapshot] = [:], errors: [UUID: String] = [:]
        var directories: [String: ServerListSnapshot] = [:]
        for preference in state.servers ?? [] {
            items[preference.id] = .init(address: preference.address, name: preference.alias.isEmpty ? preference.address.authority : preference.alias,
                                          preference: preference, instanceIDs: [], icon: nil)
        }
        for instance in state.instances {
            do {
                let key = paths.game(instance.id).standardizedFileURL.resolvingSymlinksInPath().path
                let list: ServerListSnapshot
                if let cached = directories[key] { list = cached }
                else { list = try ServerListManager(paths: paths, instanceID: instance.id).snapshot(); directories[key] = list }
                lists[instance.id] = list
                for row in list.entries {
                    guard let address = row.endpoint else { continue }
                    var item = items[address.key] ?? .init(address: address, name: row.name.isEmpty ? address.authority : row.name, preference: nil, instanceIDs: [], icon: row.icon)
                    if !item.instanceIDs.contains(instance.id) { item.instanceIDs.append(instance.id) }
                    if item.preference?.alias.isEmpty == true, !row.name.isEmpty { item.name = row.name }
                    if item.icon == nil { item.icon = row.icon }
                    items[address.key] = item
                }
            } catch { errors[instance.id] = error.localizedDescription }
        }
        var history: [String: ServerPlaySummary] = [:], historyError: String?
        do {
            for summary in try GameActivityStore.servers(paths: paths) {
                history[summary.id] = summary
                var item = items[summary.id] ?? .init(address: summary.address, name: summary.name.isEmpty ? summary.address.authority : summary.name, preference: nil, instanceIDs: [], icon: nil)
                item.playedInstanceIDs = summary.instanceIDs
                items[summary.id] = item
            }
        } catch { historyError = error.localizedDescription }
        // Break name ties by key: dictionary order changes between loads, and
        // an unstable order would reshuffle rows and restart status queries.
        let sorted = items.values.sorted { first, second in
            let order = first.name.localizedStandardCompare(second.name)
            return order == .orderedSame ? first.id < second.id : order == .orderedAscending
        }
        return .init(items: sorted, lists: lists, errors: errors, history: history, historyError: historyError)
    }
    @discardableResult public static func save(_ preference: ServerPreference, paths: LauncherPaths) throws -> PersistentState {
        try preference.validate()
        return try StateStore.updateIfChanged(paths) { state in
            var values = state.servers ?? []
            values.removeAll { $0.id == preference.id }
            if preference.favorite || !preference.alias.isEmpty || !preference.notes.isEmpty || preference.preferredInstanceID != nil { values.append(preference) }
            state.servers = values
        }
    }
}
