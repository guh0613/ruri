import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import RuriCore

enum AccountTestFixtures {
    static let uuid = "0123456789abcdef0123456789abcdef"
    static func png(width: Int = 64, height: Int = 64) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 1, alpha: 0.75)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage()), output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func paths() throws -> LauncherPaths {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        return paths
    }
}
