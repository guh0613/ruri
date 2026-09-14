import Foundation
import Testing
@testable import RuriCore

struct SkinLibraryTests {
    private func workspace() throws -> LauncherPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-skins-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return LauncherPaths(root: root)
    }

    @Test func skinsPersistAndAccountPreviewSurvivesLibraryDeletion() throws {
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths), accountID = UUID()
        #expect(try library.skins().isEmpty)
        let pixels = try PlayerTextureImage(data: AccountAppearanceTests.png())
        let saved = try library.save(name: "  Blue  ", image: pixels, model: .slim)
        #expect(saved.name == "Blue")
        #expect(try library.save(name: "Duplicate", image: pixels, model: .slim).id == saved.id)
        #expect(try library.skins().count == 1)
        try library.setPreview(saved, for: accountID)
        try library.rename(saved.id, to: "Renamed")
        let reopened = SkinLibrary(paths: paths)
        #expect(try reopened.skins().first?.name == "Renamed")
        #expect(try reopened.skins().first?.model == .slim)
        #expect(try reopened.skins().first?.image.png == pixels.png)
        try reopened.remove(saved.id)
        #expect(try reopened.skins().isEmpty)
        let preview = try #require(try reopened.preview(for: accountID))
        #expect(preview.model == .slim && preview.png == saved.png)
        try reopened.setPreview(nil, for: accountID)
        #expect(try reopened.preview(for: accountID) == nil)
    }

    @Test func sameTextureDifferentModelsRemainDistinctAndLegacyRejectsSlim() throws {
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths), image = try PlayerTextureImage(data: AccountAppearanceTests.png(width: 128, height: 128))
        let first = try library.save(name: "Classic", image: image, model: .classic)
        let second = try library.save(name: "Slim", image: image, model: .slim)
        #expect(first.id != second.id)
        #expect(try library.skins().count == 2)
        let legacy = try PlayerTextureImage(data: AccountAppearanceTests.png(height: 32))
        #expect(throws: (any Error).self) { try library.save(name: "Legacy", image: legacy, model: .slim) }
        #expect(throws: (any Error).self) { try library.save(name: "  ", image: image, model: .classic) }
        #expect(throws: (any Error).self) { try library.rename(first.id, to: String(repeating: "a", count: 81)) }
        #expect(try library.skins().count == 2)
    }

    @Test func corruptDocumentsAreReportedWithoutReplacingSavedData() throws {
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths)
        let saved = try library.save(name: "Good", image: PlayerTextureImage(data: AccountAppearanceTests.png()), model: .classic)
        let folder = paths.root.appendingPathComponent("appearance/skins")
        let corrupt = folder.appendingPathComponent(UUID().uuidString + ".json")
        try Data("invalid".utf8).write(to: corrupt)
        #expect(throws: (any Error).self) { try library.skins() }
        let listing = try library.listing()
        #expect(listing.skins.map(\.id) == [saved.id] && listing.unreadableIDs.count == 1)
        #expect(try library.save(name: "Existing", image: saved.image, model: saved.model).id == saved.id)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(saved.id.uuidString + ".json").path))
        try FileManager.default.removeItem(at: corrupt)
        #expect(try library.skins().count == 1)
    }

    @Test func skinPathsCannotEscapeThroughSymlinks() throws {
        let paths = try workspace(), outside = try workspace()
        defer { try? FileManager.default.removeItem(at: paths.root); try? FileManager.default.removeItem(at: outside.root) }
        let root = paths.root.appendingPathComponent("appearance")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("skins"), withDestinationURL: outside.root)
        let library = SkinLibrary(paths: paths)
        #expect(throws: (any Error).self) { try library.skins() }
        #expect(throws: (any Error).self) { try library.save(name: "No escape", image: PlayerTextureImage(data: AccountAppearanceTests.png()), model: .classic) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path).isEmpty)
    }

    @Test func reauthenticationPreservesAccountIdentityAndRejectsAnotherPlayer() throws {
        let original = Account(username: "OldName", uuid: "0123456789abcdef0123456789abcdef", kind: .microsoft)
        let renamed = Account(username: "NewName", uuid: "01234567-89AB-CDEF-0123-456789ABCDEF", kind: .microsoft)
        let updated = try original.reauthenticated(with: renamed)
        #expect(updated.id == original.id && updated.username == "NewName")
        #expect(throws: (any Error).self) { try original.reauthenticated(with: Account(username: "Other", uuid: String(repeating: "f", count: 32), kind: .microsoft)) }
        #expect(throws: (any Error).self) { try original.reauthenticated(with: Account(username: "Offline")) }
    }

    @Test func atlasUsesSlimArmsAndMirrorsLegacyLeftLimbs() {
        let classic = PlayerSkinLayout.faces(part: .leftArm, model: .classic, legacy: false)
        let slim = PlayerSkinLayout.faces(part: .leftArm, model: .slim, legacy: false)
        #expect(classic[0].rect == CGRect(x: 36, y: 52, width: 4, height: 12))
        #expect(slim[0].rect == CGRect(x: 36, y: 52, width: 3, height: 12))
        #expect(slim[2].rect == CGRect(x: 43, y: 52, width: 3, height: 12))
        let right = PlayerSkinLayout.faces(part: .rightLeg, model: .classic, legacy: true)
        let left = PlayerSkinLayout.faces(part: .leftLeg, model: .classic, legacy: true)
        #expect(left[0].rect == right[0].rect && left.allSatisfy(\.mirrored))
        #expect(left[1].rect == right[3].rect && left[3].rect == right[1].rect)
        #expect(PlayerSkinLayout.faces(part: .body, model: .classic, legacy: true, overlay: true).isEmpty)
        #expect(PlayerSkinLayout.faces(part: .head, model: .classic, legacy: true, overlay: true).count == 6)
        for part in PlayerSkinPart.allCases {
            for skinModel in PlayerSkinModel.allCases {
                for overlay in [true, false] {
                    #expect(PlayerSkinLayout.faces(part: part, model: skinModel, legacy: false, overlay: overlay).allSatisfy { CGRect(x: 0, y: 0, width: 64, height: 64).contains($0.rect) })
                }
            }
        }
    }
}
