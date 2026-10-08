import Foundation
import RuriLocalization

public struct GameDiagnosticDocument: Identifiable, Sendable {
    package init(
        id: String, relativePath: String? = nil, title: String, kind: Kind, text: String, isTail: Bool = false,
        truncated: Bool = false, gameRelativePath: String? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.title = title
        self.kind = kind
        self.text = text
        self.isTail = isTail
        self.truncated = truncated
        self.gameRelativePath = gameRelativePath
    }

    public enum Kind: String, Sendable { case preparation, output, gameReport, jvmReport, launcher, systemReport }
    public let id: String
    public let relativePath: String?
    public let title: String
    public let kind: Kind
    public let text: String
    public var isTail = false
    public var truncated = false
    public var gameRelativePath: String? = nil
}
