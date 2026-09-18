import CryptoKit
import Foundation

/// Profiles live for one application session. Images remain on disk and can be
/// reused when a freshly fetched profile still refers to the same texture URL.
@MainActor public final class AccountAppearanceCache {
    private let root: URL
    private var profiles: [UUID: AccountAppearance] = [:]

    public init(paths: LauncherPaths) { root = paths.root.appendingPathComponent("appearance/remote", isDirectory: true) }

    public func appearance(for account: Account) -> AccountAppearance? {
        guard let appearance = profiles[account.id], appearance.account.hasSameIdentity(as: account) else { return nil }
        return appearance
    }

    public func save(_ appearance: AccountAppearance) {
        profiles[appearance.account.id] = appearance
    }

    public func image(for texture: AccountTexture, kind: PlayerTextureKind, account: Account) throws -> PlayerTextureImage? {
        let url = try imageFile(texture, kind: kind, account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let image = try PlayerTextureImage.load(url)
        try image.validate(kind: kind, accountKind: account.kind, model: texture.model)
        return image
    }

    public func save(_ image: PlayerTextureImage, for texture: AccountTexture, kind: PlayerTextureKind, account: Account) throws {
        try image.validate(kind: kind, accountKind: account.kind, model: texture.model)
        try write(image.png, to: imageFile(texture, kind: kind, account: account))
    }

    public func invalidateAppearance(for account: Account) {
        profiles[account.id] = nil
    }

    /// Uploads on external servers may replace pixels without changing the URL.
    public func invalidateImage(for texture: AccountTexture, kind: PlayerTextureKind, account: Account) throws {
        try remove(imageFile(texture, kind: kind, account: account))
    }

    public func remove(for account: Account) throws {
        invalidateAppearance(for: account)
        try remove(LauncherPaths.safePath(account.id.uuidString, within: root))
    }

    private func imageFile(_ texture: AccountTexture, kind: PlayerTextureKind, account: Account) throws -> URL {
        let hash = SHA256.hash(data: Data(texture.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return try file(kind.rawValue + "-" + hash + ".png", for: account)
    }
    private func file(_ name: String, for account: Account) throws -> URL {
        try LauncherPaths.safePath(account.id.uuidString + "/" + name, within: root)
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
