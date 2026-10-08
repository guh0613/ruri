import Foundation
import RuriLocalization

public struct GameOutputSnapshot: Codable, Equatable, Sendable {
    package init(revision: UInt64, text: String, truncated: Bool, finished: Bool, isReplacement: Bool = true) {
        self.revision = revision
        self.text = text
        self.truncated = truncated
        self.finished = finished
        self.isReplacement = isReplacement
    }

    public let revision: UInt64
    public let text: String
    public let truncated: Bool
    public let finished: Bool
    public var isReplacement = true
}
