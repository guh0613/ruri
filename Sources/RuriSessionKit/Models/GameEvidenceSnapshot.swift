import Foundation
import RuriLocalization

public struct GameEvidenceSnapshot: Sendable {
    package init(documents: [GameDiagnosticDocument], limitations: [String]) {
        self.documents = documents
        self.limitations = limitations
    }

    public let documents: [GameDiagnosticDocument]
    public let limitations: [String]
}
