import Foundation
import Testing
@testable import RuriCore

struct MonitorSnapshotTests {
    @Test func snapshotMatchesLegacyStorageAndRejectsAnotherInstance() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let frozen = try SessionLocationSnapshot(paths: paths, instanceID: instance.id).validated(for: instance.id)
        #expect(frozen.instance(instance.id) == paths.instance(instance.id))
        #expect(frozen.game(instance.id) == paths.game(instance.id))
        let legacy = try JSONEncoder().encode(paths.monitorSnapshot(for: instance.id))
        let data = try JSONEncoder().encode(frozen)
        #expect(try JSONSerialization.jsonObject(with: legacy) as? NSDictionary == JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(throws: (any Error).self) { try frozen.validated(for: UUID()) }
        let decoded = try JSONDecoder().decode(SessionLocationSnapshot.self, from: legacy)
        #expect(try decoded.validated(for: instance.id).game(instance.id) == paths.game(instance.id))
    }
}
