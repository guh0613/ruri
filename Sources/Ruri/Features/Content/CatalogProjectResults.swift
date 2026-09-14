import SwiftUI
import RuriCore

/// Search returns a bounded page of 20 projects. Build its cells together so
/// scrolling doesn't have to instantiate rows or revise estimated heights.
struct CatalogProjectResults: View {
    let browser: CatalogBrowser

    var body: some View {
        @Bindable var browser = browser
        let projects = browser.page?.projects ?? []
        ScrollView {
            Group {
                if browser.listLayout {
                    Surface(padding: 0, shadow: false) {
                        VStack(spacing: 0) {
                            ForEach(projects) { project in
                                projectButton(project, compact: true).id(project.id)
                                if project.id != projects.last?.id {
                                    Divider().padding(.leading, 80).padding(.trailing, 18)
                                }
                            }
                        }.scrollTargetLayout()
                    }
                } else {
                    CatalogGridLayout {
                        ForEach(projects) { project in
                            projectButton(project, compact: false).id(project.id)
                        }
                    }.scrollTargetLayout()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        // Keep scrolling's observation dependency inside the results viewport,
        // separate from filters, pagination, toolbar, and navigation.
        .scrollPosition(id: $browser.scrollID, anchor: .top)
    }

    private func projectButton(_ project: CatalogProject, compact: Bool) -> some View {
        Button {
            browser.rememberSearch(); browser.open(project)
        } label: { CatalogProjectCard(project: project, compact: compact) }
            .buttonStyle(CatalogButtonStyle())
    }
}

private struct CatalogGridLayout: Layout {
    var minimumWidth: CGFloat = 360
    var spacing: CGFloat = 20

    struct Cache {
        var width: CGFloat?
        var columns = 1
        var cellSize = CGSize.zero
        var spacing: CGFloat = 0
        var minimumWidth: CGFloat = 0
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    private func prepare(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width || cache.spacing != spacing || cache.minimumWidth != minimumWidth else { return }
        cache.width = width; cache.spacing = spacing; cache.minimumWidth = minimumWidth
        cache.columns = max(1, Int((width + spacing) / (minimumWidth + spacing)))
        let cellWidth = max(0, (width - CGFloat(cache.columns - 1) * spacing) / CGFloat(cache.columns))
        let proposal = ProposedViewSize(width: cellWidth, height: nil)
        let height = subviews.map { $0.sizeThatFits(proposal).height }.max() ?? 0
        cache.cellSize = CGSize(width: cellWidth, height: height)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? minimumWidth
        prepare(width: width, subviews: subviews, cache: &cache)
        let rows = (subviews.count + cache.columns - 1) / cache.columns
        return CGSize(width: width, height: CGFloat(rows) * cache.cellSize.height + CGFloat(max(0, rows - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        prepare(width: bounds.width, subviews: subviews, cache: &cache)
        for index in subviews.indices {
            let x = bounds.minX + CGFloat(index % cache.columns) * (cache.cellSize.width + spacing)
            let y = bounds.minY + CGFloat(index / cache.columns) * (cache.cellSize.height + spacing)
            subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(cache.cellSize))
        }
    }
}
