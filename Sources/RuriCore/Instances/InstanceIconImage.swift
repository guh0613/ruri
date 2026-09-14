import RuriLocalization
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A portable image suitable for both the instance list and the game Dock icon. Original image files and their metadata are
/// never stored in launcher preferences or required after selection.
public enum InstanceIconImage {
    public static let maximumBytes = 512 * 1024
    private static let maximumDimension = 512

    public static func load(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else {
            throw RuriError.message(Messages.CoreInstanceIconImage.imageTooLarge)
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw RuriError.message(Messages.CoreInstanceIconImage.unsupportedImageFormat) }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw RuriError.message(Messages.CoreInstanceIconImage.iconSaveFailed)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RuriError.message(Messages.CoreInstanceIconImage.iconSaveFailed) }
        let result = output as Data
        try validate(result)
        return result
    }

    public static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...maximumDimension).contains(width), (1...maximumDimension).contains(height) else {
            throw RuriError.message(Messages.CoreInstanceIconImage.invalidIconImage)
        }
    }
}
