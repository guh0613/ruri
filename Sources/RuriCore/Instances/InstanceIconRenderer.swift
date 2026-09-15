import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws built-in icons with one implementation for launcher views and the
/// game's Dock icon, so both always match.
public enum InstanceIconRenderer {
    /// A square, full-bleed tile in pixel units. Callers clip it to their shape.
    public static func image(_ style: InstanceIconStyle, pixels: Int) -> CGImage? {
        guard pixels > 0, let context = bitmap(pixels) else { return nil }
        draw(style, in: context, tile: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    /// A PNG laid out on the macOS icon grid, for the game's Dock icon.
    public static func launchPNG(_ style: InstanceIconStyle) -> Data? {
        let canvas = 512, tile = CGRect(x: 50, y: 50, width: 412, height: 412)
        guard let context = bitmap(canvas) else { return nil }
        let shape = CGPath(roundedRect: tile, cornerWidth: 92, cornerHeight: 92, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.28))
        context.addPath(shape); context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fillPath()
        context.restoreGState()
        context.addPath(shape); context.clip()
        draw(style, in: context, tile: tile)
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func bitmap(_ pixels: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func texture(_ name: String) -> CGImage? {
        guard let encoded = InstanceIconTextures.png[name], let data = Data(base64Encoded: encoded),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func draw(_ style: InstanceIconStyle, in context: CGContext, tile: CGRect) {
        let gradient = style.tint.gradient
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let fill = CGGradient(colorsSpace: space, colors: [color(gradient.top), color(gradient.bottom)] as CFArray, locations: [0, 1]) {
            context.saveGState(); context.clip(to: tile)
            context.drawLinearGradient(fill, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
            context.restoreGState()
        }
        let side = tile.width
        let white = CGColor(gray: 1, alpha: 1)
        context.saveGState()
        // A faint shadow keeps white marks legible on the lighter tints.
        context.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.035, color: CGColor(gray: 0, alpha: 0.18))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(white); context.setStrokeColor(white)
        switch style.glyph.artwork {
        case .cube(let top, let left, let right):
            // The inventory view of a block: 2:1 top rhombus, faces lit as in the
            // game's GUI, textures sampled without smoothing.
            context.setShouldAntialias(false); context.interpolationQuality = .none
            let half = side * 0.33, edge = half * 1.2247, apex = CGPoint(x: tile.midX, y: tile.midY + (half + edge) / 2)
            let corner = CGPoint(x: apex.x - half, y: apex.y - half / 2), center = CGPoint(x: apex.x, y: apex.y - half)
            func face(_ name: String, origin: CGPoint, u: CGVector, v: CGVector, light: CGFloat) {
                guard let image = texture(name) else { return }
                context.saveGState()
                context.concatenate(CGAffineTransform(a: u.dx, b: u.dy, c: v.dx, d: v.dy, tx: origin.x, ty: origin.y))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if light < 1 { context.setFillColor(CGColor(gray: 0, alpha: 1 - light)); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1)) }
                context.restoreGState()
            }
            face(left, origin: CGPoint(x: corner.x, y: corner.y - edge), u: CGVector(dx: half, dy: -half / 2), v: CGVector(dx: 0, dy: edge), light: 0.8)
            face(right, origin: CGPoint(x: center.x, y: center.y - edge), u: CGVector(dx: half, dy: half / 2), v: CGVector(dx: 0, dy: edge), light: 0.6)
            face(top, origin: corner, u: CGVector(dx: half, dy: -half / 2), v: CGVector(dx: half, dy: half / 2), light: 1)
        case .outline(let key):
            let box = side * 0.54, drawing = InstanceIconArtwork.outline(for: key)
            context.translateBy(x: tile.midX - box / 2, y: tile.midY + box / 2)
            context.scaleBy(x: box / 24, y: -box / 24)
            context.setLineWidth(1.9); context.setLineCap(.round); context.setLineJoin(.round)
            context.addPath(drawing.outline); context.strokePath()
            context.addPath(drawing.fill); context.fillPath()
        case .sprite(let name):
            // Whole-pixel cells keep the sprite crisp at every size; small sprites
            // such as the heart may grow a little larger than 16-pixel items.
            guard let image = texture(name) else { break }
            let span = CGFloat(max(image.width, image.height, 10))
            var cell = max(1, (side * 0.6 / span).rounded())
            if cell > 1, cell * span > side * 0.68 { cell -= 1 }
            let width = cell * CGFloat(image.width), height = cell * CGFloat(image.height)
            context.setShouldAntialias(false); context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: (tile.midX - width / 2).rounded(), y: (tile.midY - height / 2).rounded(), width: width, height: height))
        case .symbol(let name):
            let box = side * 0.5
            let configuration = NSImage.SymbolConfiguration(pointSize: box * 0.8, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
               symbol.size.width > 0, symbol.size.height > 0 {
                let scale = min(box / symbol.size.width, box / symbol.size.height)
                let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                symbol.draw(in: CGRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2, width: size.width, height: size.height))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
