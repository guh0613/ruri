import Foundation

public struct InstallProgress: Sendable {
    public var stage: String
    public var completed: Int
    public var total: Int
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public init(_ stage: String, completed: Int = 0, total: Int = 0) {
        self.stage = stage; self.completed = completed; self.total = total
    }
}
