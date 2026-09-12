import RuriLocalization
enum Page: String, CaseIterable, Identifiable {
    case home, library, discover, downloads, accounts, java, settings
    var id: String { rawValue }
    var title: String { switch self { case .home: Messages.AppPage.titleText1.localized; case .library: Messages.AppPage.titleText2.localized; case .discover: Messages.AppPage.titleText3.localized; case .downloads: Messages.AppPage.titleText4.localized; case .accounts: Messages.AppPage.titleText5.localized; case .java: "Java"; case .settings: Messages.AppPage.titleText6.localized } }
    var symbol: String { switch self { case .home: "house"; case .library: "square.grid.2x2"; case .discover: "safari"; case .downloads: "arrow.down.circle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}
