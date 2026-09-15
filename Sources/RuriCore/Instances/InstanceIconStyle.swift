import Foundation

/// A built-in instance icon: a block or white glyph on a tinted tile. Both
/// parts are stored by identifier, so an icon chosen in a newer launcher
/// degrades to a plain tile here instead of making the instance unreadable.
public struct InstanceIconStyle: Codable, Hashable, Sendable {
    public var glyph: InstanceIconGlyph
    public var tint: InstanceIconTint
    public init(glyph: InstanceIconGlyph, tint: InstanceIconTint) { self.glyph = glyph; self.tint = tint }

    private enum CodingKeys: String, CodingKey { case glyph, tint }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        glyph = InstanceIconGlyph(rawValue: try values.decode(String.self, forKey: .glyph)) ?? .grassBlock
        tint = InstanceIconTint(rawValue: try values.decode(String.self, forKey: .tint)) ?? .slate
    }

    /// Instances without a chosen icon are told apart by their loader: each has
    /// its own mark and a colour taken from the loader's identity.
    public static func standard(for loader: LoaderKind) -> Self {
        switch loader {
        case .vanilla: .init(glyph: .grassBlock, tint: .blue)
        case .fabric, .legacyfabric: .init(glyph: .fabric, tint: .sand)
        case .quilt: .init(glyph: .quilt, tint: .purple)
        case .forge: .init(glyph: .forge, tint: .slate)
        case .neoforge: .init(glyph: .neoforge, tint: .orange)
        case .liteloader: .init(glyph: .leaf, tint: .teal)
        case .optifine: .init(glyph: .optifine, tint: .red)
        }
    }
}

/// Tile colours share one lightness and a restrained chroma (in OKLCH), so any
/// mix of them sits together in a list without one colour shouting. Each is a
/// short same-hue gradient, lighter at the top.
public enum InstanceIconTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, sand, green, teal, slate, graphite
    public var id: String { rawValue }
    /// sRGB top and bottom colours as 0xRRGGBB.
    public var gradient: (top: UInt32, bottom: UInt32) {
        switch self {
        case .blue: (0x659AD6, 0x467DB9)
        case .indigo: (0x8287CA, 0x666AAE)
        case .purple: (0x9F7DBD, 0x8360A1)
        case .pink: (0xCB7F9D, 0xAE6180)
        case .red: (0xCC6F64, 0xAF5046)
        case .orange: (0xE09159, 0xC27235)
        case .sand: (0xC3A87E, 0xA68A5F)
        case .green: (0x70AA7C, 0x518D5F)
        case .teal: (0x5DA9A8, 0x3A8C8C)
        case .slate: (0x7E8997, 0x626D7B)
        case .graphite: (0x656565, 0x4A4A4A)
        }
    }
}

public enum InstanceIconGlyph: String, Codable, CaseIterable, Identifiable, Sendable {
    // Blocks
    case grassBlock, dirt, cobblestone, oakLog, oakPlanks, craftingTable, furnace, bookshelf
    case tnt, diamondOre, bricks, obsidian, netherrack, glowstone, jackOLantern, commandBlock
    // Loader marks
    case fabric, quilt, forge, neoforge, optifine
    // Items
    case pickaxe, sword, heart, gem, potion
    // Symbols
    case house, columns, mountain, tree, leaf, flame, drop, snowflake, moon, bolt, sparkles
    case wand, shield, crown, map, controller, wrench, flask, paw, fish, tent, trophy, palette

    public enum Group: CaseIterable, Sendable { case blocks, loaders, items, symbols }
    public enum Artwork: Sendable {
        /// A block seen as in the game's inventory, by texture name.
        case cube(top: String, left: String, right: String)
        /// One of the stroked loader drawings in `InstanceIconArtwork`.
        case outline(String)
        /// A game item as a white pixel mark, by texture name.
        case sprite(String)
        case symbol(String)
    }

    public var id: String { rawValue }
    public var group: Group {
        switch self {
        case .grassBlock, .dirt, .cobblestone, .oakLog, .oakPlanks, .craftingTable, .furnace, .bookshelf,
             .tnt, .diamondOre, .bricks, .obsidian, .netherrack, .glowstone, .jackOLantern, .commandBlock: .blocks
        case .fabric, .quilt, .forge, .neoforge, .optifine: .loaders
        case .pickaxe, .sword, .heart, .gem, .potion: .items
        default: .symbols
        }
    }
    public var artwork: Artwork {
        func cube(_ all: String) -> Artwork { .cube(top: all, left: all, right: all) }
        return switch self {
        case .grassBlock: .cube(top: "grass_block_top", left: "grass_block_side", right: "grass_block_side")
        case .dirt: cube("dirt")
        case .cobblestone: cube("cobblestone")
        case .oakLog: .cube(top: "oak_log_top", left: "oak_log", right: "oak_log")
        case .oakPlanks: cube("oak_planks")
        case .craftingTable: .cube(top: "crafting_table_top", left: "crafting_table_front", right: "crafting_table_side")
        case .furnace: .cube(top: "furnace_top", left: "furnace_front", right: "furnace_side")
        case .bookshelf: .cube(top: "oak_planks", left: "bookshelf", right: "bookshelf")
        case .tnt: .cube(top: "tnt_top", left: "tnt_side", right: "tnt_side")
        case .diamondOre: cube("diamond_ore")
        case .bricks: cube("bricks")
        case .obsidian: cube("obsidian")
        case .netherrack: cube("netherrack")
        case .glowstone: cube("glowstone")
        case .jackOLantern: .cube(top: "pumpkin_top", left: "jack_o_lantern", right: "pumpkin_side")
        case .commandBlock: .cube(top: "command_block_side", left: "command_block_front", right: "command_block_side")
        case .fabric, .quilt, .forge, .neoforge, .optifine: .outline(rawValue)
        case .pickaxe, .sword, .heart, .gem, .potion: .sprite("item_\(rawValue)")
        case .house: .symbol("house.fill")
        case .columns: .symbol("building.columns.fill")
        case .mountain: .symbol("mountain.2.fill")
        case .tree: .symbol("tree.fill")
        case .leaf: .symbol("leaf.fill")
        case .flame: .symbol("flame.fill")
        case .drop: .symbol("drop.fill")
        case .snowflake: .symbol("snowflake")
        case .moon: .symbol("moon.stars.fill")
        case .bolt: .symbol("bolt.fill")
        case .sparkles: .symbol("sparkles")
        case .wand: .symbol("wand.and.stars")
        case .shield: .symbol("shield.fill")
        case .crown: .symbol("crown.fill")
        case .map: .symbol("map.fill")
        case .controller: .symbol("gamecontroller.fill")
        case .wrench: .symbol("wrench.and.screwdriver.fill")
        case .flask: .symbol("flask.fill")
        case .paw: .symbol("pawprint.fill")
        case .fish: .symbol("fish.fill")
        case .tent: .symbol("tent.fill")
        case .trophy: .symbol("trophy.fill")
        case .palette: .symbol("paintpalette.fill")
        }
    }
}
