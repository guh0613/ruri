import Foundation
import Testing
@testable import RuriCore

struct SkinLibraryTests {
    @Test func skinsPersistAndAccountPreviewSurvivesLibraryDeletion() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths), accountID = UUID()
        let pixels = try PlayerTextureImage(data: AccountTestFixtures.png())
        let saved = try library.save(name: "  Blue  ", image: pixels, model: .slim)
        #expect(try library.save(name: "Duplicate", image: pixels, model: .slim).id == saved.id)
        try library.setPreview(saved, for: accountID)
        try library.rename(saved.id, to: "Renamed")
        let reopened = SkinLibrary(paths: paths)
        let restored = try #require(try reopened.skins().first)
        #expect(restored.name == "Renamed" && restored.model == .slim && restored.png == pixels.png)
        try reopened.remove(saved.id)
        #expect(try reopened.skins().isEmpty)
        let preview = try #require(try reopened.preview(for: accountID))
        #expect(preview.model == .slim && preview.png == saved.png)
        try reopened.setPreview(nil, for: accountID)
        #expect(try reopened.preview(for: accountID) == nil)
    }

    @Test func armModelIsAnAttributeOfTheSameSkin() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths), image = try PlayerTextureImage(data: AccountTestFixtures.png(width: 128, height: 128))
        let first = try library.save(name: "Classic", image: image, model: .classic)
        let second = try library.save(name: "Slim", image: image, model: .slim)
        #expect(first.id == second.id && second.name == "Classic" && second.model == .slim)
        #expect(try library.skins().count == 1)
    }

    @Test func wearingASkinUpdatesItsSavedCopy() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths), image = try PlayerTextureImage(data: AccountTestFixtures.png())
        let saved = try library.save(name: "Blue", image: image, model: .classic)
        try library.noteWorn(image, model: .slim)
        #expect(try library.skins().map(\.model) == [.slim])
        try library.noteWorn(image, model: .classic, entry: saved.id, name: "Navy")
        let worn = try #require(try library.skins().first)
        #expect(worn.id == saved.id && worn.name == "Navy" && worn.model == .classic)
        try library.noteWorn(PlayerTextureImage(data: AccountTestFixtures.png(width: 128, height: 128)), model: .slim)
        #expect(try library.skins().count == 1)
    }

    @Test func legacyPerModelCopiesAreNotCollapsed() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths), image = try PlayerTextureImage(data: AccountTestFixtures.png())
        let classic = try SavedPlayerSkin(name: "Classic", image: image, model: .classic)
        let slim = try SavedPlayerSkin(name: "Slim", image: image, model: .slim)
        let folder = paths.root.appendingPathComponent("appearance/skins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for skin in [classic, slim] { try JSONEncoder().encode(skin).write(to: folder.appendingPathComponent(skin.id.uuidString + ".json")) }
        try library.noteWorn(image, model: .slim, entry: classic.id, name: "Renamed")
        let skins = try library.skins()
        #expect(Set(skins.map(\.model)) == [.classic, .slim])
        #expect(skins.first { $0.id == classic.id }?.name == "Renamed")
        #expect(try library.save(name: "Again", image: image, model: .slim).id == slim.id)
    }

    @Test func corruptDocumentsAreReportedWithoutReplacingSavedData() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SkinLibrary(paths: paths)
        let saved = try library.save(name: "Good", image: PlayerTextureImage(data: AccountTestFixtures.png()), model: .classic)
        let folder = paths.root.appendingPathComponent("appearance/skins")
        let corrupt = folder.appendingPathComponent(UUID().uuidString + ".json")
        try Data("invalid".utf8).write(to: corrupt)
        #expect(throws: (any Error).self) { try library.skins() }
        let listing = try library.listing()
        #expect(listing.skins.map(\.id) == [saved.id] && listing.unreadableIDs.count == 1)
        #expect(try library.save(name: "Existing", image: saved.image, model: saved.model).id == saved.id)
        #expect(try Data(contentsOf: corrupt) == Data("invalid".utf8))
    }

    @Test func skinPathsCannotEscapeThroughSymlinks() throws {
        let paths = try AccountTestFixtures.paths(), outside = try AccountTestFixtures.paths()
        defer { try? FileManager.default.removeItem(at: paths.root); try? FileManager.default.removeItem(at: outside.root) }
        let root = paths.root.appendingPathComponent("appearance")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("skins"), withDestinationURL: outside.root)
        let library = SkinLibrary(paths: paths)
        #expect(throws: (any Error).self) { try library.skins() }
        #expect(throws: (any Error).self) { try library.save(name: "No escape", image: PlayerTextureImage(data: AccountTestFixtures.png()), model: .classic) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path).isEmpty)
    }

}
