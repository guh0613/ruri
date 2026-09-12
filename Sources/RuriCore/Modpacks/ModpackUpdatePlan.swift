import RuriLocalization
import Foundation

public struct ModpackFileChange: Identifiable, Sendable {
    public enum Action: String, Sendable { case add, replace, remove, keep
        public var title: String { switch self { case .add: Messages.CoreModpackUpdatePlan.newFile.localized; case .replace: Messages.CoreModpackUpdatePlan.replacedFile.localized; case .remove: Messages.CoreModpackUpdatePlan.removedFile.localized; case .keep: Messages.CoreModpackUpdatePlan.keepLocalFile.localized } }
    }
    public let id: String
    public let previousPath: String?
    public let targetPath: String?
    public let action: Action
    public let conflict: Bool
    public let explanation: String?
    let incoming: InstalledModpack.File?
    let observed: [String: String?]
}

public struct PreparedModpackUpdate: Identifiable, Sendable {
    public let id: UUID
    public let instance: GameInstance
    public let current: InstalledModpack
    public let incoming: InstalledModpack
    public let changes: [ModpackFileChange]
    let workspace: URL
    let candidate: GameInstance
    let baselineData: Data
    let manifestData: Data
    let contentRecords: [ManagedContent]
    let keepJVMArguments: Bool
}

enum ModpackUpdatePlanner {
    static func digest(_ file: URL) throws -> String? {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil { throw RuriError.message(Messages.CoreModpackUpdatePlan.symlinkUpdateSkipped(file.lastPathComponent)) }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let info = try file.resourceValues(forKeys: [.isRegularFileKey])
        guard info.isRegularFile == true else { throw RuriError.message(Messages.CoreModpackUpdatePlan.destinationFolderExists(file.lastPathComponent)) }
        return try InstanceTransfer.sha1(file)
    }
    static func protected(_ path: String) -> Bool {
        let key = path.precomposedStringWithCanonicalMapping.lowercased()
        return InstanceTransfer.excluded.union(["saves", "screenshots", "backups", "world-backups"]).contains { key == $0 || key.hasPrefix($0 + "/") }
    }
    static func changes(from old: InstalledModpack, to new: InstalledModpack, game: URL, records: [ManagedContent]) throws -> [ModpackFileChange] {
        let oldByPath = Dictionary(uniqueKeysWithValues: old.files.map { ($0.path, $0) })
        var consumed = Set<String>(), result: [ModpackFileChange] = []
        // A manually updated or disabled mod may no longer have its pack filename.
        var aliases: [String: Set<String>] = [:]
        for record in records {
            aliases[record.provider + ":" + record.projectID, default: []].insert(record.relativePath)
        }
        let mods = game.appendingPathComponent("mods")
        if FileManager.default.fileExists(atPath: mods.path) {
            for file in try FileTree.children(in: mods) where file.lastPathComponent.hasSuffix(".jar") || file.lastPathComponent.hasSuffix(".jar.disabled") {
                if let id = ContentManager.modInfo(file)?.id { aliases["mod:" + id, default: []].insert("mods/" + file.lastPathComponent) }
            }
        }
        func actual(_ file: InstalledModpack.File) throws -> String? {
            if try digest(LauncherPaths.safePath(file.path, within: game)) != nil { return file.path }
            let disabled = file.path + ".disabled"
            if ["mods/", "resourcepacks/", "shaderpacks/"].contains(where: file.path.hasPrefix), try digest(LauncherPaths.safePath(disabled, within: game)) != nil { return disabled }
            let found = try Set(file.identities.flatMap { aliases[$0] ?? [] }).filter { try digest(LauncherPaths.safePath($0, within: game)) != nil }
            guard found.count <= 1 else { throw RuriError.message(Messages.CoreModpackUpdatePlan.duplicateLocalMatches(file.path)) }
            return found.first
        }
        func change(previous: InstalledModpack.File?, incoming: InstalledModpack.File?) throws -> ModpackFileChange? {
            let id = incoming?.path ?? previous!.path
            if protected(id) { return nil }
            let source = try previous.flatMap(actual)
            var target = incoming?.path
            if source?.hasSuffix(".disabled") == true { target = target.map { $0 + ".disabled" } }
            var observed: [String: String?] = [:]
            for path in Set([previous?.path, source, target].compactMap { $0 }) {
                observed[path] = .some(try digest(LauncherPaths.safePath(path, within: game)))
            }
            let local = source.flatMap { observed[$0] ?? nil }
            let collision = target.flatMap { observed[$0] ?? nil }
            let edited = local != previous?.sha1
            let action: ModpackFileChange.Action
            var conflict = false, explanation: String?
            if let previous, let incoming, previous.sha1 == incoming.sha1, previous.path == incoming.path { return nil }
            if previous != nil, source == nil {
                action = incoming?.force == true ? .replace : .keep
                explanation = incoming?.force == true ? Messages.CoreModpackUpdatePlan.packRequiresReadd.localized : Messages.CoreModpackUpdatePlan.locallyRemoved.localized; conflict = incoming != nil
            } else if incoming == nil {
                action = edited ? .keep : .remove; conflict = edited
                explanation = edited ? Messages.CoreModpackUpdatePlan.removedUpstreamLocallyModified.localized : nil
            } else if previous == nil && collision == incoming?.sha1 { return nil }
            else if edited && previous != nil || (collision != nil && target != source) {
                action = incoming?.force == true ? .replace : .keep; conflict = true
                explanation = incoming?.force == true ? Messages.CoreModpackUpdatePlan.replacementRequiredLocalModified.localized : Messages.CoreModpackUpdatePlan.localModificationConflict.localized
            } else { action = previous == nil ? .add : .replace }
            return .init(id: id, previousPath: source, targetPath: target, action: action, conflict: conflict, explanation: explanation, incoming: incoming, observed: observed)
        }
        for file in new.files {
            var previous = oldByPath[file.path]
            if previous == nil && !file.identities.isEmpty {
                let matches = old.files.filter { !consumed.contains($0.path) && !Set($0.identities).isDisjoint(with: file.identities) }
                guard matches.count <= 1 else { throw RuriError.message(Messages.CoreModpackUpdatePlan.multipleFilesForProject(file.path)) }
                previous = matches.first
            }
            if let previous {
                guard consumed.insert(previous.path).inserted else { throw RuriError.message(Messages.CoreModpackUpdatePlan.duplicatePackFiles(file.path)) }
            }
            if let item = try change(previous: previous, incoming: file) { result.append(item) }
        }
        for file in old.files where !consumed.contains(file.path) {
            if let item = try change(previous: file, incoming: nil) { result.append(item) }
        }
        return result.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}
