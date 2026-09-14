import Foundation
import Markdown

/// CommonMark/GFM parsing with explicit escaping for text and attributes.
/// Raw provider HTML is rendered inside CatalogDocument's restricted web view.
struct CatalogMarkdown: MarkupVisitor {
    typealias Result = String
    private var inTableHead = false
    mutating func defaultVisit(_ markup: any Markup) -> String {
        var output = ""
        for child in markup.children { output += visit(child) }
        return output
    }
    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private mutating func wrap(_ tag: String, _ node: any Markup) -> String { "<\(tag)>" + defaultVisit(node) + "</\(tag)>" }
    mutating func visitText(_ text: Markdown.Text) -> String { escaped(text.string) }
    mutating func visitParagraph(_ paragraph: Paragraph) -> String { wrap("p", paragraph) }
    mutating func visitHeading(_ heading: Heading) -> String { wrap("h\(heading.level)", heading) }
    mutating func visitEmphasis(_ emphasis: Emphasis) -> String { wrap("em", emphasis) }
    mutating func visitStrong(_ strong: Strong) -> String { wrap("strong", strong) }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String { wrap("del", strikethrough) }
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String { wrap("blockquote", blockQuote) }
    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String { wrap("ul", unorderedList) }
    mutating func visitOrderedList(_ orderedList: OrderedList) -> String { "<ol start=\"\(orderedList.startIndex)\">" + defaultVisit(orderedList) + "</ol>" }
    mutating func visitListItem(_ listItem: ListItem) -> String {
        let checkbox = listItem.checkbox.map { $0 == .checked ? "☑ " : "☐ " } ?? ""
        return "<li>" + checkbox + defaultVisit(listItem) + "</li>"
    }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String { "<pre><code>" + escaped(codeBlock.code) + "</code></pre>" }
    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String { "<code>" + escaped(inlineCode.code) + "</code>" }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "<hr>" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>" }
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { html.rawHTML }
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String { inlineHTML.rawHTML }
    mutating func visitLink(_ link: Markdown.Link) -> String {
        guard let destination = link.destination else { return defaultVisit(link) }
        return "<a href=\"" + escaped(destination) + "\">" + defaultVisit(link) + "</a>"
    }
    mutating func visitImage(_ image: Markdown.Image) -> String {
        guard let source = image.source else { return escaped(image.plainText) }
        return "<img loading=\"lazy\" src=\"" + escaped(source) + "\" alt=\"" + escaped(image.plainText) + "\" title=\"" + escaped(image.title ?? "") + "\">"
    }
    mutating func visitTable(_ table: Markdown.Table) -> String { wrap("table", table) }
    mutating func visitTableHead(_ head: Markdown.Table.Head) -> String {
        inTableHead = true
        let content = defaultVisit(head)
        inTableHead = false
        return "<thead><tr>" + content + "</tr></thead>"
    }
    mutating func visitTableBody(_ body: Markdown.Table.Body) -> String { wrap("tbody", body) }
    mutating func visitTableRow(_ row: Markdown.Table.Row) -> String { wrap("tr", row) }
    mutating func visitTableCell(_ cell: Markdown.Table.Cell) -> String { wrap(inTableHead ? "th" : "td", cell) }
}
