import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small, portable thumbnail. Original image files and their metadata are
/// never stored in launcher preferences or required after selection.
public enum InstanceIconImage {
    public static let maximumBytes = 96 * 1024
    private static let maximumDimension = 128

    public static func load(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else {
            throw RuriError.message("请选择不超过 20 MB 的图片文件。")
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw RuriError.message("无法读取这张图片，请选择 PNG、JPEG 或其他受支持的图片。") }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw RuriError.message("无法保存实例图标。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RuriError.message("无法保存实例图标。") }
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
            throw RuriError.message("实例图标无效，请重新选择图片。")
        }
    }
}
