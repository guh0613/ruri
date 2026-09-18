import RuriCore
import RuriLocalization

extension ResourcePackCompatibility {
    var title: String {
        switch self {
        case .compatible: Messages.ContentDetails.compatible.localized
        case .tooOld: Messages.ContentDetails.packTooOld.localized
        case .tooNew: Messages.ContentDetails.packTooNew.localized
        case .invalid: Messages.ContentDetails.invalidPackMetadata.localized
        case .missingMetadata: Messages.ContentDetails.missingPackMetadata.localized
        case .unknown: Messages.ContentDetails.unknownCompatibility.localized
        }
    }
}
