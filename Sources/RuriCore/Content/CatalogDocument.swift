import Foundation
import Markdown

/// Provider prose is untrusted web content. The document has no scripts, forms,
/// frames, local-file access or remote styles; navigation is handled by the app.
public enum CatalogDocument {
    public static func html(_ text: String, isHTML: Bool, dark: Bool) -> String {
        var renderer = CatalogMarkdown()
        let content = isHTML ? text : renderer.visit(Document(parsing: text))
        let foreground = dark ? "#ededed" : "#202020"
        let muted = dark ? "#98989d" : "#636366"
        let background = dark ? "#242424" : "#ffffff"
        let surface = dark ? "#303030" : "#f5f5f7"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; script-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        :root { color-scheme: \(dark ? "dark" : "light"); }
        html, body { margin: 0; padding: 0; background: \(background); color: \(foreground); }
        body { font: 14px/1.65 -apple-system, BlinkMacSystemFont, sans-serif; padding: 22px 26px; overflow-wrap: anywhere; }
        h1,h2,h3,h4 { line-height: 1.3; margin: 1.3em 0 .6em; font-weight: 650; } h1 { font-size: 26px; } h2 { font-size: 21px; } h3 { font-size: 17px; }
        body > :first-child { margin-top: 0; } p { margin: .7em 0; }
        a { color: \(dark ? "#64a9ff" : "#0066cc"); text-decoration: none; } a:hover { text-decoration: underline; }
        img, video { max-width: 100% !important; height: auto; border-radius: 6px; } iframe, form, object, embed { display: none; }
        pre { background: \(surface); padding: 14px; border-radius: 10px; overflow-x: auto; } code { font: 12px/1.5 ui-monospace, monospace; }
        blockquote { margin: 16px 0; padding: 0 16px; border-left: 3px solid \(muted); color: \(muted); }
        table { border-collapse: collapse; display: block; overflow: auto; } th,td { padding: 8px 12px; border: 1px solid \(muted); }
        hr { border: none; border-top: 1px solid \(muted); opacity: .3; margin: 24px 0; }
        </style></head><body>\(content)</body></html>
        """
    }
}
