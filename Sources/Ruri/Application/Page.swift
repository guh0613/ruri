enum Page: String, CaseIterable, Identifiable {
    case home, library, discover, downloads, accounts, java, settings
    var id: String { rawValue }
    var title: String { switch self { case .home: "开始游戏"; case .library: "游戏实例"; case .discover: "发现内容"; case .downloads: "下载任务"; case .accounts: "账号"; case .java: "Java 运行时"; case .settings: "设置" } }
    var symbol: String { switch self { case .home: "play.circle"; case .library: "square.grid.2x2"; case .discover: "safari"; case .downloads: "arrow.down.circle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}
