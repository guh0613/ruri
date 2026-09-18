import SwiftUI

/// Places identity, launch, and management controls without using the title's
/// unwrapped width as a breakpoint. Long names wrap within the identity column.
struct HomeFeaturedHeaderLayout: Layout {
    private let columnSpacing: CGFloat = 28
    // An 80-point icon, a 20-point gap, and at least 220 points for the title.
    private let minimumIdentityWidth: CGFloat = 320
    private let actionSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 720
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 3 else { return [] }
        let launch = subviews[1].sizeThatFits(.unspecified)
        let management = subviews[2].sizeThatFits(.unspecified)
        let actionsWidth = max(launch.width, management.width)

        if width >= minimumIdentityWidth + columnSpacing + actionsWidth {
            let identityWidth = width - columnSpacing - actionsWidth
            let identity = subviews[0].sizeThatFits(ProposedViewSize(width: identityWidth, height: nil))
            let actionsHeight = launch.height + actionSpacing + management.height
            let height = max(identity.height, actionsHeight)
            let actionsY = (height - actionsHeight) / 2
            return [
                CGRect(x: 0, y: (height - identity.height) / 2, width: identityWidth, height: identity.height),
                CGRect(x: width - launch.width, y: actionsY, width: launch.width, height: launch.height),
                CGRect(x: width - management.width, y: actionsY + launch.height + actionSpacing,
                       width: management.width, height: management.height)
            ]
        }

        let identity = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let identityFrame = CGRect(x: 0, y: 0, width: width, height: identity.height)
        let actionsY = identity.height + rowSpacing
        if management.width + actionSpacing + launch.width <= width {
            let actionsHeight = max(launch.height, management.height)
            return [
                identityFrame,
                CGRect(x: width - launch.width, y: actionsY + (actionsHeight - launch.height) / 2,
                       width: launch.width, height: launch.height),
                CGRect(x: width - launch.width - actionSpacing - management.width,
                       y: actionsY + (actionsHeight - management.height) / 2,
                       width: management.width, height: management.height)
            ]
        }

        // Keep both actions together and trailing-aligned even when a longer
        // localized button title prevents the compact action row from fitting.
        return [
            identityFrame,
            CGRect(x: width - launch.width, y: actionsY, width: launch.width, height: launch.height),
            CGRect(x: width - management.width, y: actionsY + launch.height + actionSpacing,
                   width: management.width, height: management.height)
        ]
    }
}
