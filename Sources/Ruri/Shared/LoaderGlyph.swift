import AppKit
import SwiftUI
import RuriCore

/// Original monochrome drawings inspired by the loaders' recognizable marks.
/// They use a shared 24-point grid and rounded strokes, not raster logos or SF
/// Symbols assets. Template rendering follows the surrounding text and theme.
@MainActor enum LoaderGlyph {
    private static var images: [String: NSImage] = [:]

    static func image(for loader: String) -> Image {
        let key = loader == "legacy-fabric" ? "fabric" : loader
        guard ["fabric", "forge", "neoforge", "quilt", "optifine"].contains(key) else {
            let symbol = LoaderKind.allCases.first { $0.modrinthLoader == loader }?.symbol
                ?? (loader == "iris" ? "camera.aperture" : loader == "canvas" ? "paintpalette" : "square.stack.3d.up")
            return Image(systemName: symbol)
        }
        if let image = images[key] { return Image(nsImage: image) }
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let drawing = InstanceIconArtwork.outline(for: key)
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 24, y: rect.height / 24)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(drawing.outline); context.strokePath()
            context.addPath(drawing.fill); context.fillPath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        images[key] = image
        return Image(nsImage: image)
    }
}
