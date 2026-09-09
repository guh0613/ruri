import Foundation
import RuriCore

@main struct Monitor {
    @MainActor static func main() async {
        guard CommandLine.arguments.dropFirst() == ["run"] else { exit(2) }
        exit(await GameMonitorService.runFromStandardInput())
    }
}
