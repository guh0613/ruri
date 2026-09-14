import SwiftUI

/// Wraps controls or labels at their natural width without truncating a whole
/// row when the window narrows. Each row centers its shorter items vertically.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8
    struct Item { let index: Int; let size: CGSize }
    struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    struct Cache {
        var idealSizes: [CGSize]
        var spacing: CGFloat
        var rowsByWidth: [CGFloat: [Row]] = [:]
    }
    func makeCache(subviews: Subviews) -> Cache {
        Cache(idealSizes: subviews.map { $0.sizeThatFits(.unspecified) }, spacing: spacing)
    }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }
    private func rows(width: CGFloat?, subviews: Subviews, cache: inout Cache) -> [Row] {
        let limit = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? .greatestFiniteMagnitude
        if cache.idealSizes.count != subviews.count || cache.spacing != spacing { cache = makeCache(subviews: subviews) }
        if let rows = cache.rowsByWidth[limit] { return rows }
        var result: [Row] = [], row = Row()
        for index in subviews.indices {
            let ideal = cache.idealSizes[index]
            let size = ideal.width <= limit ? ideal : subviews[index].sizeThatFits(ProposedViewSize(width: limit, height: nil))
            let gap = row.items.isEmpty ? 0 : spacing
            if !row.items.isEmpty, row.width + gap + size.width > limit {
                result.append(row); row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }
        if !row.items.isEmpty { result.append(row) }
        // Layout may probe several widths; keep resizing from growing the cache.
        if cache.rowsByWidth.count >= 4 { cache.rowsByWidth.removeAll(keepingCapacity: true) }
        cache.rowsByWidth[limit] = result
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let rows = rows(width: proposal.width, subviews: subviews, cache: &cache)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews, cache: &cache) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }
}
