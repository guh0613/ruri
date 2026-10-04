import AppKit
import SwiftUI

/// Reserve toolbar space across the leading columns, so the collection only
/// needs that space itself when the sidebar is hidden. The constraints participate
/// in AppKit's sidebar animation without waiting for columnVisibility to update.
struct CollectionColumnSizing: NSViewRepresentable {
    @Binding var width: CGFloat
    let toolbarWidth: CGFloat

    func makeNSView(context: Context) -> AttachmentView { AttachmentView() }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.preferredWidth = width
        view.toolbarWidth = toolbarWidth
        view.onResize = { width = $0 }
        view.configure()
    }

    static func dismantleNSView(_ view: AttachmentView, coordinator: ()) { view.detach() }

    final class AttachmentView: NSView {
        var preferredWidth: CGFloat = 280
        var toolbarWidth: CGFloat = 420
        var onResize: ((CGFloat) -> Void)?
        private weak var splitView: NSSplitView?
        private weak var collectionView: NSView?
        private var toolbarConstraint: NSLayoutConstraint?
        private var preferredConstraint: NSLayoutConstraint?
        private var mouseMonitor: Any?
        private var isResizing = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { configure() }
        }

        func configure() {
            // SwiftUI attaches the hosting views after updating the representable.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let split = view as? NSSplitView,
                   let controller = split.delegate as? NSSplitViewController,
                   controller.splitViewItems.count == 3,
                   isDescendant(of: controller.splitViewItems[1].viewController.view) {
                    if splitView !== split {
                        detach()
                        splitView = split
                        let item = controller.splitViewItems[1]
                        let collection = item.viewController.view
                        collectionView = collection
                        // On macOS 26 the collection extends beneath the sidebar;
                        // its safe area still describes just the visible list.
                        let minimum: NSLayoutConstraint
                        if split.userInterfaceLayoutDirection == .rightToLeft {
                            minimum = split.rightAnchor.constraint(greaterThanOrEqualTo: collection.leftAnchor, constant: toolbarWidth)
                        } else {
                            minimum = collection.rightAnchor.constraint(greaterThanOrEqualTo: split.leftAnchor, constant: toolbarWidth)
                        }
                        let preferred = collection.safeAreaLayoutGuide.widthAnchor.constraint(equalToConstant: preferredWidth)
                        // Restore the user's width after the toolbar reservation
                        // is no longer needed, ahead of AppKit's width retention.
                        preferred.priority = NSLayoutConstraint.Priority(item.holdingPriority.rawValue + 1)
                        toolbarConstraint = minimum
                        preferredConstraint = preferred
                        NSLayoutConstraint.activate([minimum, preferred])
                        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                            self?.resizeDivider(event) == true ? nil : event
                        }
                    }
                    toolbarConstraint?.constant = toolbarWidth
                    if !isResizing { preferredConstraint?.constant = preferredWidth }
                    return
                }
                ancestor = view.superview
            }
        }

        private var measuredWidth: CGFloat {
            guard let collectionView else { return preferredWidth }
            let insets = collectionView.safeAreaInsets
            return collectionView.bounds.width - insets.left - insets.right
        }

        private func resizeDivider(_ event: NSEvent) -> Bool {
            guard event.window === window, event.clickCount == 1,
                  let splitView, let collectionView else { return false }
            let point = splitView.convert(event.locationInWindow, from: nil)
            let frame = collectionView.convert(collectionView.bounds, to: splitView)
            let edge = splitView.userInterfaceLayoutDirection == .rightToLeft ? frame.minX : frame.maxX
            guard splitView.bounds.contains(point), abs(point.x - edge) <= max(3, splitView.dividerThickness) else { return false }
            let originalWidth = measuredWidth
            isResizing = true
            preferredConstraint?.isActive = false
            // AppKit's divider limits use the collection's fitting size, which
            // doesn't include the neighboring sidebar. Its own 280pt minimum
            // is sufficient while the sidebar is visible.
            if let controller = splitView.delegate as? NSSplitViewController,
               controller.splitViewItems.first?.isCollapsed == false {
                toolbarConstraint?.isActive = false
            }
            splitView.layoutSubtreeIfNeeded()
            // setPosition still applies the native split-view delegate's limits.
            // Track explicitly because its cached drag range was calculated with
            // the toolbar and preferred-width constraints still installed.
            splitView.setPosition(edge, ofDividerAt: 1)
            while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                             until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                let location = splitView.convert(next.locationInWindow, from: nil)
                splitView.setPosition(edge + location.x - point.x, ofDividerAt: 1)
                if next.type == .leftMouseUp { break }
            }
            finishResize(originalWidth: originalWidth)
            return true
        }

        private func finishResize(originalWidth: CGFloat) {
            guard isResizing, window != nil else { return }
            let width = measuredWidth
            if abs(width - originalWidth) > 1 {
                preferredWidth = width
                onResize?(width)
            }
            preferredConstraint?.constant = preferredWidth
            toolbarConstraint?.isActive = true
            preferredConstraint?.isActive = true
            isResizing = false
        }

        func detach() {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
            toolbarConstraint?.isActive = false
            preferredConstraint?.isActive = false
            toolbarConstraint = nil
            preferredConstraint = nil
            collectionView = nil
            splitView = nil
            isResizing = false
        }
    }
}
