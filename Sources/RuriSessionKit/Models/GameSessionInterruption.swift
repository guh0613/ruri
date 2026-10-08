import Foundation
import RuriLocalization

public struct GameSessionInterruption: Codable, Equatable, Sendable {
    package init(
        resolution: Resolution, observedAt: Date, previousStage: GameSession.Stage, explanation: String,
        explanationMessage: LocalizedMessage? = nil
    ) {
        self.resolution = resolution
        self.observedAt = observedAt
        self.previousStage = previousStage
        self.explanation = explanation
        self.explanationMessage = explanationMessage
    }

    public enum Resolution: String, Codable, Sendable { case knownProcessEnded, userConfirmedEnded }
    public let resolution: Resolution
    public let observedAt: Date
    public let previousStage: GameSession.Stage
    public let explanation: String
    public var explanationMessage: LocalizedMessage? = nil
    public var displayExplanation: String { explanationMessage?.localized ?? explanation }
}
