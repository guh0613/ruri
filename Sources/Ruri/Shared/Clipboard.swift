import AppKit
import SwiftUI
import RuriLocalization

/// Copies plain text. Use `CopyButton` or `CopyMenuButton` so people can see
/// that it worked; VoiceOver hears it either way.
@MainActor enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        AccessibilityNotification.Announcement(Messages.Common.copied.localized).post()
    }
}

/// A copy button that turns into a checkmark for a moment. Its label keeps
/// its place underneath, so the button and everything beside it stay put.
struct CopyButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let text: () -> String
    @State private var copied = false
    @State private var copies = 0

    init(_ title: String, text: @escaping @autoclosure () -> String) {
        self.title = title; self.text = text
    }

    var body: some View {
        Button {
            Clipboard.copy(text())
            withAnimation(.snappy(duration: 0.2)) { copied = true }
            copies += 1
        } label: {
            Label(title, systemImage: "doc.on.doc")
                .opacity(copied ? 0 : 1)
                .overlay {
                    Image(systemName: "checkmark")
                        .opacity(copied ? 1 : 0)
                        .scaleEffect(copied || reduceMotion ? 1 : 0.6)
                }
        }
        .help(title)
        .accessibilityLabel(title)
        .task(id: copies) {
            guard copies > 0 else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = false }
        }
    }
}

/// A copy command for a menu. The menu closes as it's chosen, so the nearest
/// `copyNotices()` confirms it at the bottom of its area instead.
struct CopyMenuButton: View {
    @Environment(CopyNotice.self) private var notice: CopyNotice?
    let title: String
    let text: () -> String

    init(_ title: String, text: @escaping @autoclosure () -> String) {
        self.title = title; self.text = text
    }

    var body: some View {
        Button(title, systemImage: "doc.on.doc") {
            Clipboard.copy(text())
            notice?.show()
        }
    }
}

extension View {
    /// Shows the notice for menu copies made within this view. A sheet gives
    /// its content one of its own, since the window's would be behind it.
    func copyNotices() -> some View { modifier(CopyNoticeHost()) }
}

@MainActor @Observable fileprivate final class CopyNotice {
    private(set) var visible = false
    private(set) var count = 0
    func show() {
        withAnimation(.snappy(duration: 0.25)) { visible = true }
        count += 1
    }
    func hide() { withAnimation(.easeOut(duration: 0.3)) { visible = false } }
}

private struct CopyNoticeHost: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notice = CopyNotice()
    func body(content: Content) -> some View {
        content
            .environment(notice)
            .overlay(alignment: .bottom) {
                if notice.visible {
                    CopyNoticeLabel().padding(.bottom, 24)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
            }
            .task(id: notice.count) {
                guard notice.count > 0 else { return }
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                notice.hide()
            }
    }
}

private struct CopyNoticeLabel: View {
    var body: some View {
        let label = Label(Messages.Common.copied.localized, systemImage: "checkmark")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
        Group {
            if #available(macOS 26, *) {
                label.glassEffect(.regular, in: Capsule())
            } else {
                label
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
        }
        // The announcement already speaks it.
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
