import RuriLocalization
enum Page: String, CaseIterable, Identifiable {
    case home, library, discover, activity, accounts, java, settings
    var id: String { rawValue }
    var title: String { switch self { case .home: Messages.AppPage.home.localized; case .library: Messages.AppPage.library.localized; case .discover: Messages.AppPage.discover.localized; case .activity: Messages.LauncherLog.title.localized; case .accounts: Messages.AppPage.accounts.localized; case .java: "Java"; case .settings: Messages.AppPage.settings.localized } }
    var symbol: String { switch self { case .home: "house"; case .library: "square.grid.2x2"; case .discover: "safari"; case .activity: "list.bullet.rectangle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}
