import AppKit
import SwiftUI
import WebKit
import RuriCore

struct CatalogDocumentView: NSViewRepresentable {
    let text: String
    var isHTML = false
    var baseURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let key = "\(colorScheme):\(isHTML):\(text)"
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        context.coordinator.awaitingDocument = true
        context.coordinator.baseURL = baseURL
        view.loadHTMLString(CatalogDocument.html(text, isHTML: isHTML, dark: colorScheme == .dark), baseURL: baseURL)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var key = ""
        var awaitingDocument = false
        var baseURL: URL?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if awaitingDocument, action.navigationType == .other, action.targetFrame?.isMainFrame == true {
                awaitingDocument = false
                return .allow
            }
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .cancel }
            if url.fragment != nil {
                var target = URLComponents(url: url, resolvingAgainstBaseURL: false)
                target?.fragment = nil
                var document = baseURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
                document?.fragment = nil
                if target?.url == document?.url { return .allow }
            }
            if CatalogMetadata.webURL(url.absoluteString) != nil { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }
}
