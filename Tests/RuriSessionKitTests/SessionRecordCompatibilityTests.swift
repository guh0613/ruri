import Foundation
import Testing
@testable import RuriSessionKit

struct SessionRecordCompatibilityTests {
    // Frozen v1 payload: moving the Swift type must not change on-disk records.
    private let legacy = #"""
    {
      "schema": 1,
      "id": "22222222-2222-2222-2222-222222222222",
      "instanceID": "11111111-1111-1111-1111-111111111111",
      "instanceName": "Fixture", "gameVersion": "1.21.1", "loader": "vanilla",
      "memoryMB": 4096, "operatingSystem": "macOS", "hostArchitecture": "arm64",
      "accountMode": "offline", "ownerPID": 123, "createdAt": 0, "updatedAt": 3,
      "state": "failed", "stage": "finished", "debugLogging": false,
      "revision": 2, "finalSnapshot": true, "events": [], "evidence": [],
      "exit": {
        "status": 7, "reason": "exit", "processID": 456,
        "startedAt": 0, "endedAt": 3, "stopRequested": false, "durationSeconds": 3
      }
    }
    """#

    @Test func legacyRecordRetainsItsWireShapeAndUnknownOptionalValues() throws {
        let data = Data(legacy.utf8)
        let record = try JSONDecoder().decode(GameSession.self, from: data)
        try record.validate()
        #expect(record.playedSeconds == 3)
        #expect(record.exit?.shellStatus == 7)
        #expect(record.memory == nil && record.activity == nil && record.host == nil)
        let original = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? NSDictionary)
        #expect(original == encoded)
    }

    @Test func invalidStoredEvidenceCannotEscapeTheSessionDirectory() throws {
        var record = try JSONDecoder().decode(GameSession.self, from: Data(legacy.utf8))
        record.evidence = [.init(relativePath: "reports/../../state.json", name: "invalid", truncated: false)]
        #expect(throws: (any Error).self) { try record.validate() }
    }
}
