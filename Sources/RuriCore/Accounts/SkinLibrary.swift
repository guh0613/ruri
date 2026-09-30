import Foundation
import RuriLocalization

/// Each saved skin is a self-contained, atomically written document. Account
/// previews are independent copies, so deleting a library item cannot break one.
public struct SavedPlayerSkin: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let model: PlayerSkinModel
    public let png: Data
    public let createdAt: Date
    public var image: PlayerTextureImage { get throws { try PlayerTextureImage(data: png) } }

    public init(id: UUID = UUID(), name: String, image: PlayerTextureImage, model: PlayerSkinModel, createdAt: Date = Date()) throws {
        try image.validate(kind: .skin, accountKind: .offline, model: model)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw RuriError.message(Messages.AccountCenter.invalidSkinName) }
        self.id = id; self.name = name; self.model = model; self.png = image.png; self.createdAt = createdAt
    }
}

public struct SkinLibraryListing: Sendable {
    public let skins: [SavedPlayerSkin]
    public let unreadableIDs: [UUID]
}

public struct SkinLibrary: Sendable {
    private let root: URL
    public init(paths: LauncherPaths) { root = paths.root.appendingPathComponent("appearance", isDirectory: true) }

    public var directoryURL: URL { root.appendingPathComponent("skins") }
    public func listing() throws -> SkinLibraryListing {
        let folder = try directory("skins")
        guard FileManager.default.fileExists(atPath: folder.path) else { return .init(skins: [], unreadableIDs: []) }
        var skins: [SavedPlayerSkin] = [], unreadable: [UUID] = []
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            do {
                let skin = try read(url)
                guard skin.id == id else { throw RuriError.message(Messages.AccountCenter.invalidSavedSkin) }
                skins.append(skin)
            } catch { unreadable.append(id) }
        }
        return .init(skins: skins.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }, unreadableIDs: unreadable)
    }

    public func skins() throws -> [SavedPlayerSkin] {
        let folder = try directory("skins")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .map { try read($0) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
    }

    /// Pixels identify a saved skin; the arm model is one of its attributes.
    /// Saving pixels the library already holds adopts the new arm model on
    /// that entry rather than adding a second copy.
    @discardableResult public func save(name: String, image: PlayerTextureImage, model: PlayerSkinModel) throws -> SavedPlayerSkin {
        let skin = try SavedPlayerSkin(name: name, image: image, model: model)
        let same = try listing().skins.filter { $0.png == skin.png }
        if let exact = same.first(where: { $0.model == model }) { return exact }
        if let existing = same.first { return try update(existing.id, model: model) }
        try write(skin, to: file(skin.id, folder: "skins"))
        return skin
    }

    public func rename(_ id: UUID, to name: String) throws { try update(id, name: name) }

    @discardableResult public func update(_ id: UUID, name: String? = nil, model: PlayerSkinModel? = nil) throws -> SavedPlayerSkin {
        let url = try file(id, folder: "skins"), original = try read(url)
        let updated = try SavedPlayerSkin(id: id, name: name ?? original.name, image: original.image, model: model ?? original.model, createdAt: original.createdAt)
        try write(updated, to: url)
        return updated
    }

    /// Keeps the library in step with a skin that was just put on: the saved
    /// copy of those pixels takes the arm model it was worn with, and the name
    /// too when the player picked that copy (`entry`) and edited it. Libraries
    /// from before arm models were attributes may hold one copy per model;
    /// those are left alone rather than collapsed into identical twins.
    public func noteWorn(_ image: PlayerTextureImage, model: PlayerSkinModel, entry: UUID? = nil, name: String? = nil) throws {
        let same = try listing().skins.filter { $0.png == image.png }
        guard let target = same.first(where: { $0.id == entry }) ?? same.first(where: { $0.model == model }) ?? same.first else { return }
        let twin = same.contains { $0.id != target.id && $0.model == model }
        let newModel = twin ? target.model : model
        let newName = target.id == entry ? name ?? target.name : target.name
        guard newModel != target.model || newName != target.name else { return }
        try update(target.id, name: newName, model: newModel)
    }

    public func remove(_ id: UUID) throws { try FileManager.default.removeItem(at: file(id, folder: "skins")) }

    public func preview(for accountID: UUID) throws -> SavedPlayerSkin? {
        let url = try file(accountID, folder: "accounts")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url)
    }

    public func setPreview(_ skin: SavedPlayerSkin?, for accountID: UUID) throws {
        let url = try file(accountID, folder: "accounts")
        if let skin { try write(skin, to: url) }
        else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func cape(for accountID: UUID) throws -> PlayerTextureImage? {
        let url = try capeFile(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let image = try PlayerTextureImage.load(url)
        try image.validate(kind: .cape, accountKind: .offline)
        return image
    }
    public func setCape(_ image: PlayerTextureImage?, for accountID: UUID) throws {
        let url = try capeFile(accountID)
        if let image {
            try image.validate(kind: .cape, accountKind: .offline)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.png.write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func capeFile(_ id: UUID) throws -> URL { try LauncherPaths.safePath("capes/" + id.uuidString + ".png", within: root) }

    private func directory(_ name: String) throws -> URL { try LauncherPaths.safePath(name, within: root) }
    private func file(_ id: UUID, folder: String) throws -> URL { try LauncherPaths.safePath(folder + "/" + id.uuidString + ".json", within: root) }
    private func read(_ url: URL) throws -> SavedPlayerSkin {
        let safe = try LauncherPaths.safePath(url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent, within: root)
        let values = try safe.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= PlayerTextureImage.maximumBytes * 2 else {
            throw RuriError.message(Messages.AccountCenter.invalidSavedSkin)
        }
        let skin = try JSONDecoder().decode(SavedPlayerSkin.self, from: Data(contentsOf: safe))
        return try SavedPlayerSkin(id: skin.id, name: skin.name, image: skin.image, model: skin.model, createdAt: skin.createdAt)
    }
    private func write(_ skin: SavedPlayerSkin, to url: URL) throws {
        _ = try SavedPlayerSkin(id: skin.id, name: skin.name, image: skin.image, model: skin.model, createdAt: skin.createdAt)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(skin).write(to: url, options: .atomic)
    }
}
