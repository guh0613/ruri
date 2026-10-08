import Foundation
import RuriLocalization

public enum LaunchDestination: Equatable, Codable, Sendable {
    case normal
    case world(folder: String)
    case server(ServerAddress)
    public static func resolve(worldFolder: String?, serverAddress: String?) throws -> Self {
        guard worldFolder == nil || serverAddress == nil else { throw RuriError.message(Messages.Servers.destinationConflict) }
        if let worldFolder { return .world(folder: worldFolder) }
        if let serverAddress { return .server(try ServerAddress(serverAddress)) }
        return .normal
    }
}
