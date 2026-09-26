import Foundation
import Testing
import RuriCore
import RuriLocalization
@testable import RuriCommandKit

@MainActor struct CLILanguageTests {
    private func containsChinese(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }
    private func run(_ arguments: [String]) async -> (Int32, CommandCapture) {
        let capture = CommandCapture()
        let status = await CLIApplication.run(arguments, write: capture.write)
        return (status, capture)
    }
    @Test func defaultEnglishIgnoresInheritedUILanguageAndExplicitChineseDoesNotLeak() async throws {
        let chinese = LocalizationContext(language: "zh-Hans")
        let initial = await LocalizationContext.$current.withValue(chinese) { await run(["help", "config"]) }
        #expect(initial.0 == 0)
        let english = String(decoding: initial.1.output, as: UTF8.self)
        #expect(english.contains("Read explicit and effective configuration"))
        #expect(english.contains("Configuration fields"))
        #expect(!containsChinese(english))
        let explicit = await run(["--language", "zh-Hans", "help", "config"])
        #expect(explicit.0 == 0)
        #expect(String(decoding: explicit.1.output, as: UTF8.self).contains("查询显式配置"))
        #expect(containsChinese(String(decoding: explicit.1.output, as: UTF8.self)))
        let again = await run(["help", "config"])
        #expect(again.1.output == initial.1.output)
        #expect(LocalizationContext(language: "zh-Hans").string(Messages.CLISetup.title) == "命令行工具")
        #expect(!LocalizationContext.supportedLanguages.contains("en"))
    }
    @Test func everyHelpAndSchemaDescriptionUsesEnglishByDefault() async throws {
        for spec in CommandRegistry.commands {
            let result = await run(spec.path + ["--help"])
            #expect(result.0 == 0)
            let text = String(decoding: result.1.output, as: UTF8.self)
            #expect(!containsChinese(text), "\(spec.path): \(text)")
        }
        for arguments in [["--help"], ["help", "--all"], ["schema", "--full", "--json"]] {
            let result = await run(arguments)
            #expect(result.0 == 0)
            #expect(!containsChinese(String(decoding: result.1.output, as: UTF8.self)))
        }
    }
    @Test func resultsErrorsAndWarningsUseTheInvocationLanguage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suffix = ["--data-dir", root.path]
        for arguments in [
            ["instance", "list"], ["app", "info"],
            ["config", "set", "memory.maximumMB", "8192", "--scope", "defaults", "--dry-run"],
            ["config", "get"], ["config", "set", "java.major", "1", "--scope", "defaults"],
            ["instance", "list", "--limit", "invalid"],
            ["config", "set", "memory", "{\"mode\":\"manual\",\"maximumMB\":512,\"initialMB\":4096}", "--scope", "defaults"]
        ] {
            let result = await run(arguments + suffix)
            let text = String(decoding: result.1.output + result.1.errors, as: UTF8.self)
            #expect(!containsChinese(text), "\(arguments): \(text)")
        }
        let englishError = await run(["config", "get", "--json"])
        let chineseError = await run(["config", "get", "--json", "--language=zh-Hans"])
        #expect(englishError.0 == 2 && chineseError.0 == 2)
        #expect(try englishError.1.value["error"]["code"] == chineseError.1.value["error"]["code"])
        #expect(try englishError.1.value["error"]["message"].string == "Missing --scope.")
        #expect(try containsChinese(#require(chineseError.1.value["error"]["message"].string)))
        let output = CommandCapture()
        let sink = LocalizationContext.$current.withValue(.commandLine()) {
            CommandOutput(format: .text, write: output.write)
        }
        await Task.detached {
            sink.result(.object(["changed": .bool(false)]), warnings: ["fixture"])
        }.value
        #expect(String(decoding: output.errors, as: UTF8.self) == "Warning: fixture\n")
    }
    @Test func sharedProgressUsesEnglishWithoutChangingGUIStrings() {
        let cli = LocalizationContext.commandLine()
        #expect(cli.language == "en")
        #expect(cli.string(Messages.AppActivityItem.preparing) == "Preparing")
        #expect(cli.string(Messages.CoreBuildConfiguration.developmentVersion) == "Development")
        let gui = LocalizationContext(language: "zh-Hans")
        #expect(gui.string(Messages.AppActivityItem.preparing) == "准备中")
    }
}
