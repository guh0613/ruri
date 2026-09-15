import CoreGraphics

/// Original monochrome loader marks, stroked on a shared 24-point grid and
/// inspired by the loaders' recognizable marks rather than their logos.
public enum InstanceIconArtwork {
    /// Paths use a flipped 24 × 24 grid: the origin is the top-left corner.
    public static func outline(for loader: String) -> (outline: CGPath, fill: CGPath) {
        let path = CGMutablePath(), fill = CGMutablePath()
        func move(_ x: CGFloat, _ y: CGFloat) { path.move(to: CGPoint(x: x, y: y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: CGPoint(x: x, y: y)) }
        func curve(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        }
        switch loader {
        case "fabric":
            // Diagonally unrolled cloth, with a rolled upper edge and one fold.
            move(12.2, 3.1)
            curve(13.2, 2.1, 14.8, 2.1, 15.8, 3.1)
            line(21, 8.3)
            curve(22.2, 9.5, 22.2, 11.3, 21, 12.5)
            curve(20, 13.5, 18.5, 13.5, 17.5, 12.5)
            line(9.4, 20.6)
            curve(8.4, 21.6, 6.8, 21.6, 5.8, 20.6)
            line(2.7, 17.5)
            curve(1.7, 16.5, 1.7, 14.9, 2.7, 13.9)
            line(11.4, 5.2)
            curve(11, 4.5, 11.4, 3.9, 12.2, 3.1)
            path.closeSubpath()
            move(11.4, 5.2); line(18.1, 11.9)
            curve(18.8, 12.6, 19.9, 12.5, 20.3, 11.8)
            move(7.1, 10.1); line(13.8, 16.2)
        case "forge":
            // Broad anvil face, narrow waist and substantial base.
            move(2.5, 4); line(21.5, 4); line(21.5, 7.5)
            line(16, 11); line(15, 11); line(15, 14)
            curve(15, 16.2, 17, 17.2, 19.8, 18.2)
            line(20.5, 20.5); line(3.5, 20.5); line(4.2, 18.2)
            curve(7, 17.2, 9, 16.2, 9, 14)
            line(9, 11); line(8, 11); line(2.5, 7.5); path.closeSubpath()
            move(2.5, 7.5); line(21.5, 7.5)
            move(5, 18); line(19, 18)
        case "neoforge":
            // Fox ears, cheek mask and pointed muzzle remain legible at 14 pt.
            move(3, 2.8); line(9, 6.2)
            curve(11, 5.4, 13, 5.4, 15, 6.2)
            line(21, 2.8); line(20.4, 11.5)
            curve(20.1, 16.1, 16, 19.5, 12, 21.8)
            curve(8, 19.5, 3.9, 16.1, 3.6, 11.5)
            path.closeSubpath()
            move(3.6, 10); curve(7.6, 10, 9.4, 13.4, 12, 17)
            curve(14.6, 13.4, 16.4, 10, 20.4, 10)
            fill.addEllipse(in: CGRect(x: 6.3, y: 10.9, width: 1.9, height: 1.9))
            fill.addEllipse(in: CGRect(x: 15.8, y: 10.9, width: 1.9, height: 1.9))
            fill.move(to: CGPoint(x: 9.8, y: 16.5))
            fill.addLine(to: CGPoint(x: 14.2, y: 16.5))
            fill.addLine(to: CGPoint(x: 12, y: 19)); fill.closeSubpath()
        case "quilt":
            // Patchwork sheet with the characteristic round lower-right patch.
            move(4, 2.5); line(20, 2.5)
            curve(20.8, 2.5, 21.5, 3.2, 21.5, 4)
            line(21.5, 13.5)
            curve(17, 13.5, 13.5, 17, 13.5, 21.5)
            line(4, 21.5); curve(3.2, 21.5, 2.5, 20.8, 2.5, 20)
            line(2.5, 4); curve(2.5, 3.2, 3.2, 2.5, 4, 2.5)
            path.closeSubpath()
            move(8.8, 2.5); line(8.8, 21.5)
            move(15.2, 2.5); line(15.2, 14.6)
            move(2.5, 8.8); line(21.5, 8.8)
            move(2.5, 15.2); line(14.6, 15.2)
            fill.addEllipse(in: CGRect(x: 16.5, y: 16.5, width: 5, height: 5))
        case "optifine":
            // The OF monogram, drawn geometrically instead of depending on a font.
            path.addRoundedRect(in: CGRect(x: 2.5, y: 5, width: 8, height: 14), cornerWidth: 3.8, cornerHeight: 3.8)
            move(15, 19); line(15, 5); line(22, 5)
            move(15, 11.5); line(21, 11.5)
        default: break
        }
        return (path, fill)
    }
}
