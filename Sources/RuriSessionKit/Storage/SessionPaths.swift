import Foundation

/// A session uses frozen locations; storage never loads launcher configuration.
public protocol SessionPaths: Sendable {
    var root: URL { get }
    func instance(_ id: UUID) -> URL
    func game(_ id: UUID) -> URL
}
