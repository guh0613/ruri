import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import RuriLocalization

/// An immutable copy of the selected skin travels to the game monitor over its
/// existing stdin pipe. Later account edits cannot affect an already running game.
public struct OfflineSkinLaunch: Codable, Sendable {
    public let account: Account
    public let skin: SavedPlayerSkin?
    public let capePNG: Data?
    public let injector: URL
    var argumentIndex: Int?

    public init(account: Account, skin: SavedPlayerSkin?, cape: PlayerTextureImage? = nil, injector: URL) throws {
        guard account.kind == .offline, injector.isFileURL,
              account.uuid.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        guard skin != nil || cape != nil else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        self.account = account; self.injector = injector
        if let skin {
            let image = try skin.image
            try image.validate(kind: .skin, accountKind: .offline, model: skin.model)
            self.skin = try SavedPlayerSkin(id: skin.id, name: skin.name, image: Self.standardImage(image), model: skin.model, createdAt: skin.createdAt)
        } else { self.skin = nil }
        if let cape { try cape.validate(kind: .cape, accountKind: .offline); capePNG = try Self.standardCape(cape).png }
        else { capePNG = nil }
    }

    func validate() throws {
        guard account.kind == .offline, injector.isFileURL, FileManager.default.fileExists(atPath: injector.path),
              account.uuid.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              (try? Account(username: account.username)) != nil else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        guard skin != nil || capePNG != nil else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        if let skin { try skin.image.validate(kind: .skin, accountKind: .microsoft, model: skin.model) }
        if let capePNG {
            let cape = try PlayerTextureImage(data: capePNG)
            guard cape.width == 64, cape.height == 32 else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        }
    }

    private static func standardCape(_ image: PlayerTextureImage) throws -> PlayerTextureImage {
        if image.width == 64 && image.height == 32 { return image }
        let compact = image.width * 17 == image.height * 22
        guard let source = CGImageSourceCreateWithData(image.png as CFData, nil), let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        context.interpolationQuality = .none
        context.draw(full, in: compact ? CGRect(x: 0, y: 15, width: 22, height: 17) : CGRect(x: 0, y: 0, width: 64, height: 32))
        let data = NSMutableData()
        guard let resized = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        return try PlayerTextureImage(data: data as Data)
    }

    // Vanilla accepts standard resolution. Keep the HD original in the library
    // and serve a pixel-aligned 64px copy to the game without requiring a mod.
    private static func standardImage(_ image: PlayerTextureImage) throws -> PlayerTextureImage {
        if image.width == 64 { return image }
        let height = image.isLegacySkin ? 32 : 64
        guard let source = CGImageSourceCreateWithData(image.png as CFData, nil), let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: 64, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        context.interpolationQuality = .none
        context.draw(full, in: CGRect(x: 0, y: 0, width: 64, height: height))
        let data = NSMutableData()
        guard let resized = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        return try PlayerTextureImage(data: data as Data)
    }
}
