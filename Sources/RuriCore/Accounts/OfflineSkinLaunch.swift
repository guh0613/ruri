import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import RuriLocalization

extension OfflineSkinLaunch {
    public init(account: Account, skin: SavedPlayerSkin?, cape: PlayerTextureImage? = nil, injector: URL) throws {
        guard account.kind == .offline, injector.isFileURL,
              account.uuid.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
            throw RuriError.message(Messages.OfflineSkin.invalidConfiguration)
        }
        guard skin != nil || cape != nil else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        let normalizedSkin: SavedPlayerSkin?
        let normalizedCape: Data?
        if let skin {
            let image = try skin.image
            try image.validate(kind: .skin, accountKind: .offline, model: skin.model)
            normalizedSkin = try SavedPlayerSkin(id: skin.id, name: skin.name, image: Self.standardImage(image), model: skin.model, createdAt: skin.createdAt)
        } else { normalizedSkin = nil }
        if let cape { try cape.validate(kind: .cape, accountKind: .offline); normalizedCape = try Self.standardCape(cape).png }
        else { normalizedCape = nil }
        self.init(account: .init(id: account.id, username: account.username, uuid: account.uuid),
                  skin: normalizedSkin.map { .init(id: $0.id, name: $0.name, model: $0.model, png: $0.png, createdAt: $0.createdAt) },
                  capePNG: normalizedCape, injector: injector)
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
