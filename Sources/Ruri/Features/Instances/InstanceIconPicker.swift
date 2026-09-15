import RuriLocalization
import SwiftUI
import RuriCore

/// Built-in icons share a small fixed palette, so any combination stays calm
/// next to other instances. Choosing a colour or glyph replaces a custom image.
struct InstanceIconPicker: View {
    let loader: LoaderKind
    @Binding var png: Data?
    @Binding var style: InstanceIconStyle?
    let chooseImage: () -> Void
    var useModpackIcon: (() -> Void)?

    private var current: InstanceIconStyle { style ?? .standard(for: loader) }
    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group(Messages.AppInstanceIconPicker.color.localized) {
                HStack(spacing: 5) { ForEach(InstanceIconTint.allCases) { swatch($0) } }
            }
            ForEach(InstanceIconGlyph.Group.allCases, id: \.self) { kind in
                group(kind.title) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(InstanceIconGlyph.allCases.filter { $0.group == kind }) { glyphButton($0) }
                    }
                }
            }
            Divider()
            HStack {
                Button(Messages.AppInstanceSettingsView.chooseImage.localized, action: chooseImage)
                if let useModpackIcon { Button(Messages.AppInstanceIconPicker.useModpackIcon.localized, action: useModpackIcon) }
                Spacer()
            }
        }
        .padding(16).frame(width: 396)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func swatch(_ tint: InstanceIconTint) -> some View {
        let selected = png == nil && current.tint == tint
        return Button { select(.init(glyph: current.glyph, tint: tint)) } label: {
            Circle().fill(LinearGradient(colors: tint.colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay { if selected { Circle().strokeBorder(Theme.accent, lineWidth: 2) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(tint.title)
        .accessibilityLabel(tint.title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func glyphButton(_ glyph: InstanceIconGlyph) -> some View {
        let selected = png == nil && current.glyph == glyph
        return Button { select(.init(glyph: glyph, tint: current.tint)) } label: {
            InstanceIcon(loader: loader, size: 36, style: .init(glyph: glyph, tint: current.tint))
                .padding(3)
                .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 2) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(glyph.title)
        .accessibilityLabel(glyph.title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ choice: InstanceIconStyle) {
        style = choice; png = nil
    }
}

private extension InstanceIconTint {
    var colors: [Color] {
        func color(_ hex: UInt32) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        return [color(gradient.top), color(gradient.bottom)]
    }
    var title: String {
        typealias M = Messages.AppInstanceIconPicker
        return switch self {
        case .blue: M.tintBlue.localized
        case .indigo: M.tintIndigo.localized
        case .purple: M.tintPurple.localized
        case .pink: M.tintPink.localized
        case .red: M.tintRed.localized
        case .orange: M.tintOrange.localized
        case .sand: M.tintSand.localized
        case .green: M.tintGreen.localized
        case .teal: M.tintTeal.localized
        case .slate: M.tintSlate.localized
        case .graphite: M.tintGraphite.localized
        }
    }
}

private extension InstanceIconGlyph.Group {
    var title: String {
        switch self {
        case .blocks: Messages.AppInstanceIconPicker.blocks.localized
        case .loaders: Messages.AppInstanceIconPicker.loaders.localized
        case .items: Messages.AppInstanceIconPicker.items.localized
        case .symbols: Messages.AppInstanceIconPicker.symbols.localized
        }
    }
}

private extension InstanceIconGlyph {
    var title: String {
        typealias M = Messages.AppInstanceIconPicker
        return switch self {
        case .grassBlock: M.glyphGrassBlock.localized
        case .dirt: M.glyphDirt.localized
        case .cobblestone: M.glyphCobblestone.localized
        case .oakLog: M.glyphOakLog.localized
        case .oakPlanks: M.glyphOakPlanks.localized
        case .craftingTable: M.glyphCraftingTable.localized
        case .furnace: M.glyphFurnace.localized
        case .bookshelf: M.glyphBookshelf.localized
        case .tnt: M.glyphTnt.localized
        case .diamondOre: M.glyphDiamondOre.localized
        case .bricks: M.glyphBricks.localized
        case .obsidian: M.glyphObsidian.localized
        case .netherrack: M.glyphNetherrack.localized
        case .glowstone: M.glyphGlowstone.localized
        case .jackOLantern: M.glyphJackOLantern.localized
        case .commandBlock: M.glyphCommandBlock.localized
        case .fabric: LoaderKind.fabric.title
        case .quilt: LoaderKind.quilt.title
        case .forge: LoaderKind.forge.title
        case .neoforge: LoaderKind.neoforge.title
        case .optifine: LoaderKind.optifine.title
        case .pickaxe: M.glyphPickaxe.localized
        case .sword: M.glyphSword.localized
        case .heart: M.glyphHeart.localized
        case .gem: M.glyphGem.localized
        case .potion: M.glyphPotion.localized
        case .house: M.glyphHouse.localized
        case .columns: M.glyphColumns.localized
        case .mountain: M.glyphMountain.localized
        case .tree: M.glyphTree.localized
        case .leaf: M.glyphLeaf.localized
        case .flame: M.glyphFlame.localized
        case .drop: M.glyphDrop.localized
        case .snowflake: M.glyphSnowflake.localized
        case .moon: M.glyphMoon.localized
        case .bolt: M.glyphBolt.localized
        case .sparkles: M.glyphSparkles.localized
        case .wand: M.glyphWand.localized
        case .shield: M.glyphShield.localized
        case .crown: M.glyphCrown.localized
        case .map: M.glyphMap.localized
        case .controller: M.glyphController.localized
        case .wrench: M.glyphWrench.localized
        case .flask: M.glyphFlask.localized
        case .paw: M.glyphPaw.localized
        case .fish: M.glyphFish.localized
        case .tent: M.glyphTent.localized
        case .trophy: M.glyphTrophy.localized
        case .palette: M.glyphPalette.localized
        }
    }
}
