import SwiftUI
import AppKit
import SceneKit
import ImageIO
import RuriCore
import RuriLocalization

/// A rotatable character on a soft stage, with the view controls in a bar
/// along the bottom so the figure stays the focus of the panel.
struct PlayerSkinPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    var image: PlayerTextureImage?
    var model: PlayerSkinModel = .classic
    var cape: PlayerTextureImage?
    var height: CGFloat = 300
    /// Framed previews stand alone with their own border; unframed ones fill
    /// a column of a card and stretch to the card's height.
    var framed = true
    @State private var angle = -22.0
    @State private var overlays = true
    @State private var dragStart: Double?
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PlayerModelView(image: image, model: model, cape: cape, angle: angle, overlays: overlays)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: height, maxHeight: framed ? height : .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = angle }
                        let degrees = (dragStart ?? 0) + value.translation.width * 0.7
                        angle = ((degrees + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
                    }.onEnded { _ in dragStart = nil })
                    .accessibilityLabel(Messages.AccountCenter.characterPreview.localized)
            }
            .background {
                LinearGradient(colors: [.primary.opacity(colorScheme == .dark ? 0.09 : 0.06), .primary.opacity(colorScheme == .dark ? 0.02 : 0.015)],
                               startPoint: .top, endPoint: .bottom)
            }
            Divider()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "rotate.3d").foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: $angle, in: -180...180) { Text(Messages.AccountCenter.rotation.localized) }.labelsHidden().controlSize(.small)
                    Button { withAnimation(.snappy) { angle = -22 } } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help(Messages.AccountCenter.resetView.localized).accessibilityLabel(Messages.AccountCenter.resetView.localized)
                }
                Toggle(Messages.AccountCenter.outerLayer.localized, isOn: $overlays).toggleStyle(.checkbox).controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: framed ? 12 : 0, style: .continuous))
        .overlay {
            if framed {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1).allowsHitTesting(false)
            }
        }
    }
}

private struct PlayerModelView: NSViewRepresentable {
    let image: PlayerTextureImage?
    let model: PlayerSkinModel
    let cape: PlayerTextureImage?
    let angle: Double
    let overlays: Bool
    final class Coordinator {
        var png: Data?
        var capePNG: Data?
        var model: PlayerSkinModel?
        var overlays = false
        var player: SCNNode?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.isPlaying = false
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        let cache = context.coordinator
        if cache.player == nil || cache.png != image?.png || cache.capePNG != cape?.png || cache.model != model || cache.overlays != overlays {
            let scene = SCNScene(), player = SCNNode()
            scene.rootNode.addChildNode(player)
            for part in PlayerSkinPart.allCases {
                add(part, to: player, overlay: false)
                if overlays && image != nil { add(part, to: player, overlay: true) }
            }
            if let cape { addCape(cape, to: player) }
            let camera = SCNNode(); camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 19
            camera.position = SCNVector3(0, 5, 65); camera.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(camera)
            let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 650
            scene.rootNode.addChildNode(ambient)
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni; light.light?.intensity = 750
            light.position = SCNVector3(-25, 40, 45); scene.rootNode.addChildNode(light)
            view.scene = scene; view.pointOfView = camera
            cache.player = player; cache.png = image?.png; cache.capePNG = cape?.png; cache.model = model; cache.overlays = overlays
        }
        cache.player?.eulerAngles.y = CGFloat(angle * .pi / 180)
    }
    private func add(_ part: PlayerSkinPart, to parent: SCNNode, overlay: Bool) {
        let legacy = image?.isLegacySkin ?? false
        let faces = PlayerSkinLayout.faces(part: part, model: model, legacy: legacy, overlay: overlay)
        guard !faces.isEmpty else { return }
        let arm: CGFloat = model == .slim && !legacy ? 3 : 4
        let size: (CGFloat, CGFloat, CGFloat), position: SCNVector3
        switch part {
        case .head: size = (8, 8, 8); position = SCNVector3(0, 12, 0)
        case .body: size = (8, 12, 4); position = SCNVector3(0, 2, 0)
        case .rightArm: size = (arm, 12, 4); position = SCNVector3(-(8 + arm) / 2, 2, 0)
        case .leftArm: size = (arm, 12, 4); position = SCNVector3((8 + arm) / 2, 2, 0)
        case .rightLeg: size = (4, 12, 4); position = SCNVector3(-2, -10, 0)
        case .leftLeg: size = (4, 12, 4); position = SCNVector3(2, -10, 0)
        }
        let expansion: CGFloat = overlay ? (part == .head ? 1 : 0.5) : 0
        let box = SCNBox(width: size.0 + expansion, height: size.1 + expansion, length: size.2 + expansion, chamferRadius: 0)
        box.materials = faces.map { face in
            material(image.flatMap { SkinPixels.crop($0, rect: face.rect, mirrored: face.mirrored) }, overlay: overlay)
        }
        let node = SCNNode(geometry: box); node.position = position
        parent.addChildNode(node)
    }
    private func addCape(_ cape: PlayerTextureImage, to parent: SCNNode) {
        let box = SCNBox(width: 10, height: 16, length: 1, chamferRadius: 0)
        let rects = [CGRect(x: 1, y: 1, width: 10, height: 16), CGRect(x: 11, y: 1, width: 1, height: 16),
                     CGRect(x: 12, y: 1, width: 10, height: 16), CGRect(x: 0, y: 1, width: 1, height: 16),
                     CGRect(x: 1, y: 0, width: 10, height: 1), CGRect(x: 11, y: 0, width: 10, height: 1)]
        box.materials = rects.map { material(SkinPixels.crop(cape, rect: $0, baseWidth: SkinPixels.capeBaseWidth(cape)), overlay: false) }
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, 0, -3.4); node.eulerAngles.x = .pi / 18
        // The broad outer face of a cape is the front of its texture atlas.
        node.eulerAngles.y = .pi
        parent.addChildNode(node)
    }
    private func material(_ pixels: NSImage?, overlay: Bool) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = pixels ?? NSColor(white: 0.66, alpha: 1)
        result.diffuse.magnificationFilter = .nearest; result.diffuse.minificationFilter = .nearest; result.diffuse.mipFilter = .none
        result.lightingModel = .lambert; result.isDoubleSided = overlay
        result.transparencyMode = .aOne
        return result
    }
}

@MainActor enum SkinPixels {
    private static let decoded: NSCache<NSData, CGImage> = {
        let cache = NSCache<NSData, CGImage>(); cache.totalCostLimit = 32 * 1024 * 1024; cache.countLimit = 32
        return cache
    }()
    private static func fullImage(_ image: PlayerTextureImage) -> CGImage? {
        if let cached = decoded.object(forKey: image.png as NSData) { return cached }
        guard let source = CGImageSourceCreateWithData(image.png as CFData, nil), let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        decoded.setObject(full, forKey: image.png as NSData, cost: full.bytesPerRow * full.height)
        return full
    }
    /// Capes come as 64 × 32 atlases or the older 22 × 17 sheet.
    static func capeBaseWidth(_ cape: PlayerTextureImage) -> CGFloat { cape.width * 17 == cape.height * 22 ? 22 : 64 }
    static func crop(_ image: PlayerTextureImage, rect: CGRect, mirrored: Bool = false, baseWidth: CGFloat = 64) -> NSImage? {
        guard let full = fullImage(image) else { return nil }
        let scale = CGFloat(image.width) / baseWidth
        let bounds = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cropped = full.cropping(to: bounds) else { return nil }
        if mirrored, let context = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.translateBy(x: CGFloat(cropped.width), y: 0); context.scaleBy(x: -1, y: 1)
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
            if let flipped = context.makeImage() { return NSImage(cgImage: flipped, size: rect.size) }
        }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}

struct AccountAvatar: View {
    @Environment(AppModel.self) private var model
    let account: Account
    var size: CGFloat = 36
    var body: some View {
        SkinAvatar(image: model.accountSkins[account.id].flatMap { try? $0.image }, size: size)
            .task(id: account.id) { model.loadAccountPreview(account) }
    }
}

struct SkinAvatar: View {
    var image: PlayerTextureImage?
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            if let image, let face = SkinPixels.crop(image, rect: CGRect(x: 8, y: 8, width: 8, height: 8))?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                Image(decorative: face, scale: 1).resizable().interpolation(.none)
                if let hat = SkinPixels.crop(image, rect: CGRect(x: 40, y: 8, width: 8, height: 8))?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    Image(decorative: hat, scale: 1).resizable().interpolation(.none)
                }
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22)).accessibilityHidden(true)
    }
}

/// The front panel of a cape, as a small thumbnail for a list row.
struct CapeThumbnail: View {
    var image: PlayerTextureImage?
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            if let image, let front = SkinPixels.crop(image, rect: CGRect(x: 1, y: 1, width: 10, height: 16), baseWidth: SkinPixels.capeBaseWidth(image))?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                Image(decorative: front, scale: 1).resizable().interpolation(.none)
                    .aspectRatio(10 / 16, contentMode: .fit).padding(size * 0.14)
            } else {
                CapeGlyph().stroke(style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.secondary)
                    .frame(width: size * 0.5, height: size * 0.5)
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22)).accessibilityHidden(true)
    }
}

/// A cloak seen from behind, drawn as a stroked outline in the manner of SF
/// Symbols, since the system has no cape symbol of its own: a narrow collar,
/// sides that flare out as the cloth hangs, a gently rippled hem and two
/// fold lines.
struct CapeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(0.28, 0.14))
        path.addQuadCurve(to: p(0.42, 0.07), control: p(0.33, 0.07))
        path.addQuadCurve(to: p(0.58, 0.07), control: p(0.50, 0.17))
        path.addQuadCurve(to: p(0.72, 0.14), control: p(0.67, 0.07))
        path.addCurve(to: p(0.96, 0.90), control1: p(0.78, 0.36), control2: p(0.92, 0.62))
        path.addQuadCurve(to: p(0.73, 0.94), control: p(0.85, 0.99))
        path.addQuadCurve(to: p(0.50, 0.90), control: p(0.62, 0.86))
        path.addQuadCurve(to: p(0.27, 0.94), control: p(0.38, 0.86))
        path.addQuadCurve(to: p(0.04, 0.90), control: p(0.15, 0.99))
        path.addCurve(to: p(0.28, 0.14), control1: p(0.08, 0.62), control2: p(0.22, 0.36))
        path.closeSubpath()
        path.move(to: p(0.40, 0.32)); path.addQuadCurve(to: p(0.33, 0.78), control: p(0.35, 0.55))
        path.move(to: p(0.60, 0.32)); path.addQuadCurve(to: p(0.67, 0.78), control: p(0.65, 0.55))
        return path
    }
}
