import Foundation
import RuriLocalization

/// Frozen, normalized pixels and an offline identity. No account service or
/// skin-library object is available in the detached monitor.
public struct OfflineSkinLaunch: Codable, Sendable {
    public struct Player: Codable, Equatable, Sendable {
        public let id: UUID
        public let kind: String
        public let username: String
        public let uuid: String
        package init(id: UUID, username: String, uuid: String) {
            self.id = id; kind = "offline"; self.username = username; self.uuid = uuid
        }
    }
    public struct Skin: Codable, Sendable {
        public let id: UUID
        public let name: String
        public let model: PlayerSkinModel
        public let png: Data
        public let createdAt: Date
        public var image: PlayerTextureImage { get throws { try PlayerTextureImage(data: png) } }
        package init(id: UUID, name: String, model: PlayerSkinModel, png: Data, createdAt: Date) {
            self.id = id; self.name = name; self.model = model; self.png = png; self.createdAt = createdAt
        }
    }
    public let account: Player
    public let skin: Skin?
    public let capePNG: Data?
    public let injector: URL
    package var argumentIndex: Int?

    package init(account: Player, skin: Skin?, capePNG: Data?, injector: URL, argumentIndex: Int? = nil) {
        self.account = account; self.skin = skin; self.capePNG = capePNG
        self.injector = injector; self.argumentIndex = argumentIndex
    }
    package func validate() throws {
        guard account.kind == "offline", injector.isFileURL, FileManager.default.fileExists(atPath: injector.path),
              account.uuid.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              account.username.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) != nil else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        guard skin != nil || capePNG != nil else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        if let skin { try skin.image.validate(kind: .skin, standardSkinOnly: true, model: skin.model) }
        if let capePNG {
            let cape = try PlayerTextureImage(data: capePNG)
            guard cape.width == 64, cape.height == 32 else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        }
    }
}
