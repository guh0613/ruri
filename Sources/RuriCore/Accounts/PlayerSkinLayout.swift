import Foundation
import CoreGraphics

/// Minecraft's texture atlas, in logical pixels. SceneKit and thumbnail views
/// share these coordinates; HD skins simply multiply them by width / 64.
public enum PlayerSkinPart: CaseIterable, Sendable { case head, body, rightArm, leftArm, rightLeg, leftLeg }
public struct PlayerSkinFace: Sendable {
    public let rect: CGRect
    public let mirrored: Bool
}
public enum PlayerSkinLayout {
    /// Front, right, back, left, top, bottom (SCNBox material order).
    public static func faces(part: PlayerSkinPart, model: PlayerSkinModel, legacy: Bool, overlay: Bool = false) -> [PlayerSkinFace] {
        if legacy && overlay && part != .head { return [] }
        let slim = model == .slim && !legacy
        let width: CGFloat = part == .head || part == .body ? 8 : (part == .leftArm || part == .rightArm) && slim ? 3 : 4
        let height: CGFloat = part == .head ? 8 : 12, depth: CGFloat = part == .head ? 8 : 4
        let origin: CGPoint
        switch part {
        case .head: origin = CGPoint(x: overlay ? 32 : 0, y: 0)
        case .body: origin = CGPoint(x: 16, y: overlay ? 32 : 16)
        case .rightArm: origin = CGPoint(x: 40, y: overlay ? 32 : 16)
        case .leftArm: origin = legacy ? CGPoint(x: 40, y: 16) : CGPoint(x: overlay ? 48 : 32, y: 48)
        case .rightLeg: origin = CGPoint(x: 0, y: overlay ? 32 : 16)
        case .leftLeg: origin = legacy ? CGPoint(x: 0, y: 16) : CGPoint(x: overlay ? 0 : 16, y: 48)
        }
        let x = origin.x, y = origin.y
        var rects = [CGRect(x: x + depth, y: y + depth, width: width, height: height),
                     CGRect(x: x + depth + width, y: y + depth, width: depth, height: height),
                     CGRect(x: x + 2 * depth + width, y: y + depth, width: width, height: height),
                     CGRect(x: x, y: y + depth, width: depth, height: height),
                     CGRect(x: x + depth, y: y, width: width, height: depth),
                     CGRect(x: x + depth + width, y: y, width: width, height: depth)]
        let mirrored = legacy && (part == .leftArm || part == .leftLeg)
        if mirrored { rects.swapAt(1, 3) }
        return rects.map { PlayerSkinFace(rect: $0, mirrored: mirrored) }
    }
}
