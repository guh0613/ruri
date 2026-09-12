import RuriLocalization
import Foundation

/// Imported launch manifests may refer to modified client jars or local Maven
/// artifacts. Their resources travel with the instance instead of replacing
/// shared downloads used by independently installed games.
public struct ImportedMinecraftInstallation: Codable, Equatable, Sendable {
    public var version = 1
    public let sourceVersionID: String
    public let components: [MinecraftDirectoryComponent]
    public init(sourceVersionID: String, components: [MinecraftDirectoryComponent]) {
        self.sourceVersionID = sourceVersionID; self.components = components
    }
    func validate() throws {
        func validLabel(_ value: String, limit: Int) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit &&
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
        guard version == 1, validLabel(sourceVersionID, limit: 255),
              components.count <= 64, Set(components.map(\.id)).count == components.count,
              components.allSatisfy({ validLabel($0.name, limit: 128) && validLabel($0.version, limit: 128) }) else {
            throw RuriError.message(Messages.CoreImportedMinecraftInstallation.invalidInstallationMetadata)
        }
    }
}
