import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

@MainActor struct DiscoveryTests {
    @Test func completeCheatSheetIsBoundedAndContainsEverySignature() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["help", "--all"], write: output.write) == 0)
        let text = String(decoding: output.output, as: UTF8.self)
        for spec in CommandRegistry.commands { #expect(text.contains(CommandHelp.signature(spec))) }
        #expect(output.output.count < 35_000)
        #expect(!text.contains("resultSchema"))
        #expect(text.components(separatedBy: "--data-dir").count == 2)
    }
    @Test func configurationFieldsDescribeTypesRangesAndUnitsWithoutState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("broken".utf8).write(to: root.appendingPathComponent("state.json"))
        let text = CommandCapture()
        #expect(await CLIApplication.run(["config", "fields", "memory", "--data-dir", root.path], write: text.write) == 0)
        let rendered = String(decoding: text.output, as: UTF8.self)
        #expect(rendered.contains("memory.maximumMB") && rendered.contains("512–131072 MB") && rendered.contains("or null"))
        #expect(!rendered.contains("appearance"))
        let json = CommandCapture()
        #expect(await CLIApplication.run(["config", "fields", "--scope", "app", "--json", "--data-dir", root.path], write: json.write) == 0)
        let fields = try json.value["data"]["fields"].decode([Value].self)
        #expect(fields.map { $0["name"].string } == ConfigurationService.appFields.map(\.name))
        #expect(fields.first { $0["name"] == .string("concurrentDownloads") }?["maximum"] == .integer(16))
        let launch = CommandCapture()
        #expect(await CLIApplication.run(["config", "fields", "commands.", "--scope", "instance", "--json"], write: launch.write) == 0)
        #expect(try launch.value["data"]["fields"].decode([Value].self).allSatisfy { $0["group"] == .string("commands") })
        #expect(try launch.value["data"]["fields"].decode([Value].self).contains { $0["unit"] == .string("seconds") })
        let unknown = CommandCapture()
        #expect(await CLIApplication.run(["config", "fields", "memroy", "--json"], write: unknown.write) == 2)
        #expect(try unknown.value["error"]["message"].string?.contains("memory") == true)
        #expect(try String(contentsOf: root.appendingPathComponent("state.json"), encoding: .utf8) == "broken")
    }
    @Test func schemaIndexAndLeafExcludeUnrelatedDefinitions() async throws {
        let index = CommandCapture()
        #expect(await CLIApplication.run(["schema", "--json"], write: index.write) == 0)
        #expect(index.output.count < 40_000)
        #expect(try index.value["data"]["patchSchemas"] == .null)
        #expect(!String(decoding: index.output, as: UTF8.self).contains("resultSchema"))
        let leaf = CommandCapture()
        #expect(await CLIApplication.run(["schema", "instance", "list", "--json"], write: leaf.write) == 0)
        #expect(leaf.output.count < 5_000)
        #expect(try leaf.value["data"]["configuration"] == .null)
        #expect(try leaf.value["data"]["patchSchemas"] == .null)
    }
    @Test func schemaCanSelectOnlyInputOutputAndPatchScope() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["schema", "config", "apply", "--input", "--scope", "instance", "--json"], write: output.write) == 0)
        let data = try output.value["data"]
        #expect(data["patchSchemas"]["app"] == .null)
        #expect(data["patchSchemas"]["defaults"] == .null)
        #expect(data["patchSchemas"]["instance"] != .null)
        #expect(!String(decoding: output.output, as: UTF8.self).contains("resultSchema"))
        let result = CommandCapture()
        #expect(await CLIApplication.run(["schema", "config", "apply", "--output-schema", "--json"], write: result.write) == 0)
        #expect(try result.value["data"]["patchSchemas"] == .null)
        #expect(!String(decoding: result.output, as: UTF8.self).contains("inputSchema"))
        for args in [["schema", "--input"], ["schema", "instance", "list", "--scope", "app"], ["schema", "config", "get", "--scope", "app", "--output-schema"], ["help", "missing"], ["help", "--output", "missing"]] {
            let invalid = CommandCapture()
            #expect(await CLIApplication.run(args + ["--json"], write: invalid.write) == 2)
        }
    }
}
