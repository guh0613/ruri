import Foundation
import RuriCore
import RuriLocalization

@main struct Monitor {
    @MainActor static func main() async {
        if let status = LocalizationCommandLine.resourceCheck() { exit(status) }
        guard CommandLine.arguments.dropFirst() == ["run"] else { exit(2) }
        exit(await GameMonitorService.runFromStandardInput())
    }
}
