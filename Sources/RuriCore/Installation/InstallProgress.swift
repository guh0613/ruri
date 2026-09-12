import Foundation
import RuriLocalization

public struct InstallProgress: Sendable {
    public var message: LocalizedMessage
    public var stage: String { message.localized }
    public var completed: Int
    public var total: Int
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public init(_ stage: String, completed: Int = 0, total: Int = 0) {
        self.message = .verbatim(stage); self.completed = completed; self.total = total
    }
    public init(_ message: LocalizedMessage, completed: Int = 0, total: Int = 0) {
        self.message = message; self.completed = completed; self.total = total
    }
}
