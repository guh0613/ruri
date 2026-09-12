import AppKit
import SwiftUI

/// Keeps the native toolbar controls while letting the split view draw the
/// background through the titlebar. AppKit's separate toolbar backdrop can
/// overlap the sidebar divider when using the compatibility appearance.
struct TransparentWindowTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> TitlebarView { TitlebarView() }

    func updateNSView(_ nsView: TitlebarView, context: Context) {
        nsView.configureWindow()
    }

    final class TitlebarView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            // Apply after SwiftUI has installed/updated the window's toolbar.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, !window.titlebarAppearsTransparent else { return }
                window.titlebarAppearsTransparent = true
            }
        }
    }
}
