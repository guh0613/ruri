import SwiftUI
import RuriCore

enum Theme {
    /// The system accent, so custom views stay in step with sidebar icons,
    /// links and controls, and a user-chosen accent applies everywhere.
    static let accent = Color.accentColor
    // Recent macOS versions use the same color for window and control
    // backgrounds. Choose the two semantic levels explicitly in each scheme.
    static func canvas(for scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? .windowBackgroundColor : .underPageBackgroundColor)
    }
    static func surface(for scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? .underPageBackgroundColor : .controlBackgroundColor)
    }
}

struct Surface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 20
    var shadow = true
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content.padding(padding)
            .clipShape(shape)
            .background {
                if shadow {
                    shape.fill(Theme.surface(for: colorScheme))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, x: 0, y: 3)
                } else {
                    shape.fill(Theme.surface(for: colorScheme))
                }
            }
            .overlay {
                shape
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Heading for a sheet or a self-contained panel. Main pages get their title
/// from the window toolbar and use `SectionTitle` for their content groups.
struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 27, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

/// A content-group heading with an optional trailing action, in the style of
/// the shelves in Music and the App Store.
struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) { self.title = title; self.trailing = trailing() }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            trailing.font(.callout)
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

struct TagPill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.1), in: Capsule()).foregroundStyle(color) }
}

struct InstanceIcon: View {
    let loader: LoaderKind
    var size: CGFloat = 48
    var png: Data?
    var body: some View {
        Group {
            if let png, let image = InstanceIconCache.image(png) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LoaderGlyph.image(for: loader.modrinthLoader).resizable().scaledToFit()
                    .frame(width: size * 0.52, height: size * 0.52)
                    .foregroundStyle(Theme.accent)
                    .frame(width: size, height: size)
                    .background(Theme.accent.opacity(0.10))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}

@MainActor enum InstanceIconCache {
    static let images: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>(); cache.countLimit = 256; cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    static func image(_ data: Data) -> NSImage? {
        if let cached = images.object(forKey: data as NSData) { return cached }
        guard (try? InstanceIconImage.validate(data)) != nil, let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: data as NSData, cost: 128 * 128 * 4)
        return image
    }
}

/// One fact about an instance, laid out in a row of equals under a hero card.
struct StatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact colored symbols make the shortcuts easy to recognize while
/// keeping titles and descriptions in the shared grouped-list hierarchy.
struct ActionRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    var tint: Color = Theme.accent
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
                    .opacity(isEnabled ? 1 : 0.45)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(hovering ? 0.045 : 0))
        .onHover { hovering = $0 }
    }
}

/// The same shortcut as `ActionRow`, stacked into a card so a set of them can
/// spread across the full width of a page instead of crowding a side column.
struct ActionTile: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    var tint: Color = Theme.accent
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
                    .opacity(isEnabled ? 1 : 0.45)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(Theme.surface(for: colorScheme))
                .overlay { shape.fill(.primary.opacity(hovering ? 0.045 : 0)) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, x: 0, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
    }
}

extension View {
    /// Content under the toolbar fades out softly instead of ending at a hard
    /// line, where the system offers the choice.
    @ViewBuilder func softTopScrollEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }

    /// Pins controls above a scroll view as part of it, so they share the
    /// toolbar's edge effect rather than splitting the column with a divider.
    @ViewBuilder func topScrollBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar).scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: bar)
        }
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(detail) }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
