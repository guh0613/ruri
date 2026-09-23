import Foundation
import Observation
import Sparkle

/// Sparkle updates from the per-architecture appcast that the Appcast workflow
/// publishes to GitHub Pages. Items from GitHub pre-releases carry the
/// `prerelease` channel and are offered only after opting in.
@MainActor @Observable final class SoftwareUpdater: NSObject, SPUUpdaterDelegate {
    private static let prereleaseChannel = "prerelease"
    private static let prereleasePreferenceKey = "RuriReceivePrereleaseUpdates"
    #if arch(arm64)
    private static let feed = "https://guh0613.github.io/ruri/appcast-arm64.xml"
    #else
    private static let feed = "https://guh0613.github.io/ruri/appcast-x86_64.xml"
    #endif

    /// Builds run outside a packaged bundle have no update key, and Sparkle
    /// would report a startup error for them.
    let isAvailable = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = false {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    var automaticallyDownloadsUpdates = false {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }
    var receivesPrereleases = UserDefaults.standard.bool(forKey: SoftwareUpdater.prereleasePreferenceKey) {
        didSet { UserDefaults.standard.set(receivesPrereleases, forKey: Self.prereleasePreferenceKey) }
    }
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard isAvailable else { return }
        controller.startUpdater()
        let updater = controller.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func feedURLString(for updater: SPUUpdater) -> String? { Self.feed }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesPrereleases ? [Self.prereleaseChannel] : []
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }
}
