import SwiftUI

/// Shared visual treatment for version and loader labels across the app.
struct MetadataBadge: View {
    let text: String
    var symbol: String?
    var loader: String?
    var compact = false
    var suffix: String?
    var body: some View {
        HStack(spacing: 5) {
            if let loader {
                LoaderGlyph.image(for: loader).resizable().scaledToFit().frame(width: compact ? 12 : 15, height: compact ? 12 : 15).foregroundStyle(.primary.opacity(0.75)).accessibilityHidden(true)
            } else if let symbol { Image(systemName: symbol).font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(text).font(compact ? .caption.weight(.medium) : .callout.weight(.medium)).lineLimit(1)
            if let suffix {
                Text(suffix).font(compact ? .caption : .callout).foregroundStyle(.secondary)
                    .fixedSize().padding(.leading, 7)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.primary.opacity(0.15)).frame(width: 1).padding(.vertical, 2)
                    }
            }
        }
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 3 : 5)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }
}
