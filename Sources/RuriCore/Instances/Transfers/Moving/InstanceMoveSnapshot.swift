import RuriLocalization
import Foundation

struct InstanceMoveSnapshot: Sendable {
    let entries: [FileTree.Entry]
    let original: FileTreeManifest
    let destination: FileTreeManifest
    let hasPreviousData: Bool

    static func previousDataPath(_ id: UUID) -> String { "previous-run-directories/\(id.uuidString)" }

    static func capture(instance: GameInstance, paths: LauncherPaths, transactionID: UUID) throws -> Self {
        let metadata = paths.instance(instance.id)
        let before = try FileTree.entries(in: metadata, ignoringTransientFiles: false)
        let rootAttributes = try FileExtendedAttributes.capture(metadata)
        let original = try FileTreeManifest.capture(before, rootAttributes: rootAttributes)
        var files = before, hasPreviousData = false
        var sharedGame: [FileTree.Entry] = [], sharedMetadata: [FileTree.Entry] = []
        if instance.runDirectory == .shared {
            let prior = previousDataPath(transactionID)
            guard !before.contains(where: { $0.path == prior || $0.path.hasPrefix(prior + "/") }) else { throw RuriError.message(Messages.CoreInstanceMoveSnapshot.priorText1) }
            let relocated: Set<String> = ["minecraft", "content.json", "world-backups"]
            files = before.map { entry in
                guard relocated.contains(String(entry.path.split(separator: "/")[0])) else { return entry }
                hasPreviousData = true
                return entry.mapped(to: prior + "/" + entry.path)
            }
            let game = paths.game(instance.id)
            if FileManager.default.fileExists(atPath: game.path) {
                sharedGame = try FileTree.entries(in: game, excluding: [".ruri"], ignoringTransientFiles: false)
                let attributes = try game.resourceValues(forKeys: [.contentModificationDateKey])
                files.append(.init(url: game, path: "minecraft", directory: true, size: 0, modified: attributes.contentModificationDate ?? .distantPast))
                files += sharedGame.map { $0.mapped(to: "minecraft/" + $0.path) }
            }
            sharedMetadata = try sharedContentEntries(instance: instance, paths: paths)
            files += sharedMetadata
        }
        let required: Set<String> = instance.runDirectory == .shared ? ["minecraft"] : []
        let destination = try FileTreeManifest.capture(files, requiringDirectories: required, rootAttributes: rootAttributes)
        // Capture again because the mapped shared files do not all belong to the
        // metadata tree whose identity and digest guard source retirement.
        guard try FileTree.entries(in: metadata, ignoringTransientFiles: false) == before,
              try FileTreeManifest.capture(in: metadata) == original else { throw RuriError.message(Messages.CoreInstanceMoveSnapshot.destinationText1) }
        if instance.runDirectory == .shared {
            guard try FileTree.entries(in: paths.game(instance.id), excluding: [".ruri"], ignoringTransientFiles: false) == sharedGame,
                  try sharedContentEntries(instance: instance, paths: paths) == sharedMetadata else { throw RuriError.message(Messages.CoreInstanceMoveSnapshot.destinationText2) }
        }
        return .init(entries: files, original: original, destination: destination, hasPreviousData: hasPreviousData)
    }

    private static func sharedContentEntries(instance: GameInstance, paths: LauncherPaths) throws -> [FileTree.Entry] {
        try FileTree.entries(in: paths.gameDataState(instance.id), ignoringTransientFiles: false).filter {
            ["content.json", "world-backups"].contains(String($0.path.split(separator: "/")[0]))
        }
    }

    func requireUnchanged(instance: GameInstance, paths: LauncherPaths, transactionID: UUID) throws {
        let current = try Self.capture(instance: instance, paths: paths, transactionID: transactionID)
        guard current.original == original, current.destination == destination, current.entries == entries else {
            throw RuriError.message(Messages.CoreInstanceMoveSnapshot.currentText1)
        }
    }
}

private extension FileTree.Entry {
    func mapped(to path: String) -> Self { .init(url: url, path: path, directory: directory, size: size, modified: modified) }
}
