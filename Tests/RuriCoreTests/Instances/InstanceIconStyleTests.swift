import Foundation
import Testing
@testable import RuriCore

struct InstanceIconStyleTests {
    @Test func unknownIdentifiersFromNewerLaunchersFallBack() throws {
        let data = Data(#"{"glyph":"future-glyph","tint":"future-tint"}"#.utf8)
        let style = try JSONDecoder().decode(InstanceIconStyle.self, from: data)
        #expect(style == InstanceIconStyle(glyph: .grassBlock, tint: .slate))
    }

    @Test func styleRoundTripsWithInstance() throws {
        var instance = GameInstance(name: "Pack", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.16.0")
        instance.iconStyle = .init(glyph: .pickaxe, tint: .teal)
        let decoded = try JSONDecoder().decode(GameInstance.self, from: JSONEncoder().encode(instance))
        #expect(decoded.iconStyle == instance.iconStyle)
        let portable = try PortableInstance(instance).instance()
        #expect(portable.iconStyle == instance.iconStyle)
    }

    @Test func launchIconIsAValidInstanceImage() throws {
        for loader in LoaderKind.allCases {
            let png = try #require(InstanceIconRenderer.launchPNG(.standard(for: loader)))
            try InstanceIconImage.validate(png)
        }
    }
}
