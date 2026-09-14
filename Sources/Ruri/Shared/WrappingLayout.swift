import SwiftUI

/// Wraps controls or labels at their natural width without truncating a whole
/// row when the window narrows. Each row centers its shorter items vertically.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8
    private struct Item { let index: Int; let size: CGSize }
    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    private func rows(width: CGFloat?, subviews: Subviews) -> [Row] {
        let limit = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? .greatestFiniteMagnitude
        var result: [Row] = [], row = Row()
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: min(ideal.width, limit), height: nil))
            let gap = row.items.isEmpty ? 0 : spacing
            if !row.items.isEmpty, row.width + gap + size.width > limit {
                result.append(row); row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }
        if !row.items.isEmpty { result.append(row) }
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }
}
