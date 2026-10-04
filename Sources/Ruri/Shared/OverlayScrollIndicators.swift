import AppKit
import SwiftUI

/// Attach inside a ScrollView's content to keep its artwork behind the native
/// scroller instead of reserving an opaque scrollbar gutter.
struct OverlayScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> AttachmentView { AttachmentView() }
    func updateNSView(_ view: AttachmentView, context: Context) { view.configure() }
    static func dismantleNSView(_ view: AttachmentView, coordinator: ()) { view.detach() }

    final class AttachmentView: NSView {
        private weak var scrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { configure() }
        }

        func configure() {
            // SwiftUI finishes attaching and configuring the native scroll view
            // after updating this representable.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, let scroll = self.enclosingScrollView else { return }
                if self.scrollView !== scroll {
                    self.detach()
                    self.scrollView = scroll
                    // AppKit can reapply the preferred style after window setup
                    // or a system preference change. Keep this override local.
                    self.styleObservation = scroll.observe(\.scrollerStyle, options: [.new]) { [weak self] _, change in
                        guard change.newValue != .overlay else { return }
                        DispatchQueue.main.async { [weak self] in self?.applyStyle() }
                    }
                }
                self.applyStyle()
            }
        }

        func detach() {
            styleObservation = nil
            scrollView?.scrollerStyle = NSScroller.preferredScrollerStyle
            scrollView = nil
        }

        private func applyStyle() {
            guard window != nil, let scrollView, scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.documentView?.needsLayout = true
        }
    }
}
