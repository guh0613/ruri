import RuriLocalization
import SwiftUI

struct FactStripItem: Identifiable {
    let id: String
    let label: String
    let value: String
    var detail: String?
    var action: (() -> Void)?
}

/// One row of equal columns split by hairlines, like the facts under an
/// App Store title; it scrolls sideways when the page is too narrow.
struct FactStrip: View {
    let items: [FactStripItem]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(expanded: true)
            ScrollView(.horizontal, showsIndicators: false) { row(expanded: false) }
        }
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func row(expanded: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().frame(height: 36) }
                FactStripCell(item: item).frame(minWidth: 104, maxWidth: expanded ? .infinity : nil)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct FactStripCell: View {
    let item: FactStripItem
    @State private var hovering = false
    var body: some View {
        if let action = item.action {
            Button(action: action) { cell.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .background(.primary.opacity(hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        } else {
            cell
        }
    }
    private var cell: some View {
        VStack(spacing: 4) {
            Text(item.label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(item.value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            // Cells that open a manager say so with a link-coloured line, so
            // every cell keeps three lines and none reads as a blank gap.
            if item.action != nil {
                HStack(spacing: 2) {
                    Text(item.detail ?? Messages.AppLibraryView.manage.localized)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.caption).foregroundStyle(Theme.accent).lineLimit(1)
            } else {
                Text(item.detail ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
}

/// An accent "Title ›" link for the trailing edge of a `SectionTitle`.
struct SectionLink: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) { Text(title); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
    }
}
