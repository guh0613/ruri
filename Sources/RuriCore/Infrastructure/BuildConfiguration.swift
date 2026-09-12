import RuriLocalization
import Foundation

/// Public defaults embedded in the application before it is signed.
public struct BuildConfiguration: Sendable {
    public let microsoftClientID: String
    public let version: String

    public init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        microsoftClientID = (info["RuriMicrosoftClientID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        version = info["RuriVersion"] as? String ?? info["CFBundleShortVersionString"] as? String ?? Messages.CoreBuildConfiguration.developmentVersion.localized
    }

    public func microsoftClientID(override: String) -> String {
        let value = override.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? microsoftClientID : value
    }
}
