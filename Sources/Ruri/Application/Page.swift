enum Page: String, CaseIterable, Identifiable {
    case home, library, discover, downloads, accounts, java, settings
    var id: String { rawValue }
    var title: String { switch self { case .home: "主页"; case .library: "实例库"; case .discover: "发现"; case .downloads: "下载"; case .accounts: "账号"; case .java: "Java"; case .settings: "设置" } }
    var symbol: String { switch self { case .home: "house"; case .library: "square.grid.2x2"; case .discover: "safari"; case .downloads: "arrow.down.circle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}
