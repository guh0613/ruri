import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func drawIcon(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scale: scale); (transform as NSAffineTransform).concat()
    let body = NSBezierPath(roundedRect: NSRect(x: 85, y: 85, width: 854, height: 854), xRadius: 193, yRadius: 193)
    NSGradient(starting: NSColor(red: 0.27, green: 0.50, blue: 0.42, alpha: 1), ending: NSColor(red: 0.10, green: 0.27, blue: 0.22, alpha: 1))!.draw(in: body, angle: -90)
    func poly(_ points: [(CGFloat, CGFloat)], color: NSColor) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: points[0].0, y: points[0].1))
        for v in points.dropFirst() { p.line(to: NSPoint(x: v.0, y: v.1)) }; p.close(); color.setFill(); p.fill()
    }
    poly([(512,780),(770,632),(512,484),(254,632)], color: NSColor(red: 0.88, green: 0.91, blue: 0.74, alpha: 1))
    poly([(254,632),(512,484),(512,205),(254,353)], color: NSColor(red: 0.55, green: 0.73, blue: 0.58, alpha: 1))
    poly([(512,484),(770,632),(770,353),(512,205)], color: NSColor(red: 0.36, green: 0.59, blue: 0.46, alpha: 1))
    poly([(355,574),(411,542),(411,460),(355,492)], color: NSColor(red: 0.81, green: 0.87, blue: 0.66, alpha: 1))
    poly([(592,443),(649,476),(649,390),(592,357)], color: NSColor(red: 0.26, green: 0.47, blue: 0.36, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for dimension in [16, 32, 128, 256, 512] {
    try drawIcon(size: dimension).write(to: output.appendingPathComponent("icon_\(dimension)x\(dimension).png"))
    try drawIcon(size: dimension * 2).write(to: output.appendingPathComponent("icon_\(dimension)x\(dimension)@2x.png"))
}
