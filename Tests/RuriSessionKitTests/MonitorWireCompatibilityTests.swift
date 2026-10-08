import Foundation
import Testing
@testable import RuriSessionKit

struct MonitorWireCompatibilityTests {
    @Test func legacyControlFrameHasTheSameEncodedFields() throws {
        let data = Data(#"{"version":1,"id":"22222222-2222-2222-2222-222222222222","sessionID":"11111111-1111-1111-1111-111111111111","monitor":{"pid":123,"startSeconds":100,"startMicroseconds":42},"command":"stop","output":false}"#.utf8)
        let frame = try JSONDecoder().decode(MonitorControlRequest.self, from: data)
        #expect(frame.version == 1 && frame.command == .stop && !frame.output)
        let old = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? NSDictionary)
        #expect(old == encoded)
    }

    @Test func legacyOfflineIdentityDecodesWithoutAccountServices() throws {
        let data = Data(#"{"account":{"id":"11111111-1111-1111-1111-111111111111","kind":"offline","username":"Player","uuid":"0123456789abcdef0123456789abcdef"},"injector":"file:///tmp/injector.jar","argumentIndex":3}"#.utf8)
        let value = try JSONDecoder().decode(OfflineSkinLaunch.self, from: data)
        #expect(value.account.username == "Player" && value.argumentIndex == 3)
        #expect(value.skin == nil && value.capePNG == nil)
        let old = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary)
        #expect(old == encoded)
    }
}
