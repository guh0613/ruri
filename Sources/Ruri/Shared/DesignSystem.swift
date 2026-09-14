import SwiftUI
import RuriCore

enum Theme {
    /// The system accent, so custom views stay in step with sidebar icons,
    /// links and controls, and a user-chosen accent applies everywhere.
    static let accent = Color.accentColor
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.065), lineWidth: 1))
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

@MainActor private enum InstanceIconCache {
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

/// A large tappable shortcut: icon, title and one line of detail. Used for
/// the quick actions on the home page.
struct ActionTile: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .background(hovering ? AnyShapeStyle(.primary.opacity(0.035)) : AnyShapeStyle(.background), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.065), lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

/// A dashed placeholder that closes a grid with its creation action, like
/// the "new" tile in a template chooser.
struct DashedTile: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            .foregroundStyle(hovering ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .background(hovering ? Theme.accent.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5])).foregroundStyle(.primary.opacity(0.18)))
        .onHover { hovering = $0 }
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
