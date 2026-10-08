import RuriLocalization
import Foundation

public enum GameRunDirectory: String, Codable, CaseIterable, Sendable, Identifiable {
    case isolated, shared, custom
    public var id: String { rawValue }
    public var title: String { switch self { case .isolated: Messages.CoreGameRunDirectory.isolatedDirectory.localized; case .shared: Messages.CoreGameRunDirectory.sharedDirectory.localized; case .custom: Messages.CoreGameRunDirectory.customDirectory.localized } }
    public var explanation: String {
        switch self {
        case .isolated: Messages.CoreGameRunDirectory.isolatedDirectoryDescription.localized
        case .shared: Messages.CoreGameRunDirectory.sharedDirectoryDescription.localized
        case .custom: Messages.CoreGameRunDirectory.customDirectoryDescription.localized
        }
    }
}
