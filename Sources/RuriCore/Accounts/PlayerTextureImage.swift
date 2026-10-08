import RuriSessionKit

extension PlayerTextureImage {
    public func validate(kind: PlayerTextureKind, accountKind: Account.Kind, model: PlayerSkinModel = .classic) throws {
        try validate(kind: kind, standardSkinOnly: accountKind == .microsoft, model: model)
    }
}
