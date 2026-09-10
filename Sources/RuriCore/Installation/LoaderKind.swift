import Foundation

public enum LoaderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case vanilla, fabric, quilt, forge, neoforge
    public var id: String { rawValue }
    public var title: String { switch self { case .vanilla: "原版"; case .fabric: "Fabric"; case .quilt: "Quilt"; case .forge: "Forge"; case .neoforge: "NeoForge" } }
    public var symbol: String { switch self { case .vanilla: "cube.fill"; case .fabric: "square.stack.3d.up.fill"; case .quilt: "square.grid.3x3.fill"; case .forge: "hammer.fill"; case .neoforge: "flame.fill" } }
    public var usesInstaller: Bool { self == .forge || self == .neoforge }
}
