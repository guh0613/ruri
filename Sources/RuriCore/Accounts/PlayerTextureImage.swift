import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PlayerTextureKind: String, CaseIterable, Sendable { case skin, cape
    public var title: String { self == .skin ? "皮肤" : "披风" }
}
public enum PlayerSkinModel: String, CaseIterable, Sendable { case classic, slim
    public var title: String { self == .classic ? "经典（宽手臂）" : "纤细（窄手臂）" }
}

public struct PlayerTextureImage: Sendable {
    public static let maximumBytes = 4 * 1024 * 1024
    public let png: Data
    public let width: Int
    public let height: Int
    public var isLegacySkin: Bool { width == height * 2 }

    public static func load(_ file: URL) throws -> Self {
        let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size <= maximumBytes else { throw invalid() }
        return try Self(data: Data(contentsOf: file))
    }
    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier, CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...2048).contains(width), (1...2048).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Self.invalid() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw Self.invalid() }
        // Upload only the pixel image; leave ancillary metadata out of the new PNG.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= Self.maximumBytes else { throw Self.invalid() }
        self.png = output as Data; self.width = width; self.height = height
    }
    public func validate(kind: PlayerTextureKind, accountKind: Account.Kind, model: PlayerSkinModel = .classic) throws {
        switch kind {
        case .skin:
            let valid = width.isMultiple(of: 64) && (height == width || height * 2 == width)
            guard valid, accountKind != .microsoft || width == 64 else {
                throw RuriError.message(accountKind == .microsoft ? "Microsoft 皮肤需要 64 × 64 或 64 × 32 的 PNG。" : "皮肤尺寸需要是 64 × 64 或 64 × 32 的整数倍。")
            }
            guard model != .slim || !isLegacySkin else { throw RuriError.message("旧版长方形皮肤只支持经典手臂，请使用 64 × 64 格式设置纤细手臂。") }
        case .cape:
            guard (width.isMultiple(of: 64) && height * 2 == width) || (width.isMultiple(of: 22) && height * 22 == width * 17) else {
                throw RuriError.message("披风尺寸需要是 64 × 32 或 22 × 17 的整数倍。")
            }
        }
    }
    private static func invalid() -> RuriError { .message("请选择不超过 4 MB、尺寸不超过 2048 × 2048 的单张 PNG 图片。") }
}
