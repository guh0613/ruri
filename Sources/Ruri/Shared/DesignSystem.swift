import SwiftUI
import RuriCore

enum Theme {
    static let accent = Color(red: 0.23, green: 0.47, blue: 0.39)
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
                Image(systemName: loader.symbol).font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(loader == .vanilla ? Theme.accent : Color.orange.opacity(0.8))
                    .frame(width: size, height: size)
                    .background((loader == .vanilla ? Theme.accent : Color.orange).opacity(0.10))
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

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(detail) }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
