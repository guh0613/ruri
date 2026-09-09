import SwiftUI
import AppKit
import RuriCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: "cube.transparent.fill").font(.system(size: 29, weight: .medium)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ruri").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("MINECRAFT LAUNCHER").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 23).padding(.top, 23).padding(.bottom, 28)
                List(selection: $model.page) {
                    Section("游戏") { ForEach([Page.home, .library, .discover, .downloads]) { page in sidebarRow(page) } }
                    Section("管理") { ForEach([Page.accounts, .java, .settings]) { page in sidebarRow(page) } }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                Spacer(minLength: 0)
                if let task = model.activeActivity {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.caption.weight(.medium)).lineLimit(1)
                        ProgressView(value: task.progress.fraction).tint(Theme.accent)
                        Text(task.progress.stage).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(18).onTapGesture { model.page = .downloads }
                }
                Divider().padding(.horizontal, 16)
                Button { model.page = .accounts } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.square.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.activeAccount?.username ?? "添加玩家账号").font(.system(size: 12, weight: .semibold))
                            Text(model.activeAccount.map { $0.kind == .microsoft ? "Microsoft 账号" : "离线模式" } ?? "准备好你的下一场冒险").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
                    }.padding(18)
                }.buttonStyle(.plain)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 218, max: 250)
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice {
                    HStack { Image(systemName: "info.circle"); Text(notice).font(.callout); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(12).background(Theme.accent.opacity(0.08))
                }
                Group {
                    switch model.page {
                    case .home: HomeView()
                    case .library: LibraryView()
                    case .discover: DiscoverView()
                    case .downloads: DownloadsView()
                    case .accounts: AccountsView()
                    case .java: JavaView()
                    case .settings: PreferencesView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color(nsColor: .windowBackgroundColor))
                .navigationTitle(model.page.title)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.runningID != nil { Button { model.showLogs = true } label: { Label("运行日志", systemImage: "terminal") } }
                        Button { model.showCreate = true } label: { Label("新建实例", systemImage: "plus") }.help("新建实例 ⌘N").disabled(model.busy)
                    }
                }
        }
        .tint(Theme.accent)
        .frame(minWidth: 1000, minHeight: 700)
        .preferredColorScheme(model.colorScheme)
        .sheet(isPresented: $model.showCreate) { CreateInstanceView() }
        .sheet(isPresented: $model.showAccount) { AddAccountView() }
        .sheet(isPresented: $model.showLogs) { LogsView() }
        .sheet(item: $model.editingInstance) { instance in InstanceSettingsView(instance: instance) }
        .sheet(item: $model.contentInstance) { instance in InstanceContentView(instance: instance) }
        .sheet(item: $model.worldInstance) { instance in WorldManagerView(instance: instance) }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好", role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .task { await model.boot() }
    }
    private func sidebarRow(_ page: Page) -> some View {
        Label(page.title, systemImage: page.symbol).font(.system(size: 13)).padding(.vertical, 5).tag(page)
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    SectionHeading(title: "今天，想去哪里？", subtitle: "你的世界，在 Mac 上继续。")
                    Spacer()
                    Label(JavaRuntime.hostArchitecture == "aarch64" ? "Apple Silicon" : "Intel Mac", systemImage: "laptopcomputer").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
                hero
                if let instance = model.selected {
                    HStack { Text("继续冒险").font(.title3.weight(.semibold)); Spacer(); Button("全部实例", systemImage: "arrow.right") { model.page = .library }.buttonStyle(.plain).font(.callout).foregroundStyle(Theme.accent) }
                    Surface {
                        HStack(spacing: 16) {
                            InstanceIcon(loader: instance.loader, size: 60)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(instance.name).font(.headline)
                                Text(instance.subtitle).font(.callout).foregroundStyle(.secondary)
                                HStack(spacing: 8) { TagPill(text: model.runningID == instance.id ? "运行中" : instance.installed ? "就绪" : "未完成安装"); Text(instance.lastPlayed.map { "上次游玩 \($0.formatted(.relative(presentation: .named)))" } ?? "一个全新的开始").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            launchButton(instance)
                        }
                    }
                }
                HStack(spacing: 16) {
                    quickCard("建立新世界", detail: "原版与主流模组加载器", symbol: "plus.square.on.square", action: { model.showCreate = true })
                    quickCard("发现更多可能", detail: "模组、光影与整合包", symbol: "sparkles", action: { model.page = .discover })
                    quickCard("准备好出发", detail: model.activeAccount == nil ? "添加你的 Minecraft 账号" : "管理账号与玩家身份", symbol: "person.crop.circle", action: { model.page = .accounts })
                }
                HStack(spacing: 7) {
                    Circle().fill(model.catalog == nil ? Color.orange : Theme.accent).frame(width: 5, height: 5)
                    Text(model.catalog.map { "最新正式版 \($0.latest.release)" } ?? (model.catalogLoading ? "正在获取版本信息…" : "暂时无法获取版本信息"))
                    Spacer(); Text("用心为 macOS 打造").foregroundStyle(.tertiary)
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 1250)
        }
    }
    private var hero: some View {
        ZStack(alignment: .leading) {
            Landscape()
            LinearGradient(colors: [Theme.sand.opacity(0.97), Theme.sand.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                Text("A LITTLE WONDER. A WHOLE NEW WORLD.").font(.system(size: 9, weight: .bold)).tracking(1.7).foregroundStyle(Theme.ink.opacity(0.6))
                Text("下一个世界，\n从这里开始。").font(.system(size: 35, weight: .bold, design: .rounded)).lineSpacing(6).foregroundStyle(Theme.ink)
                Text("熟悉的方块，无限的可能。\n选择一个版本，让冒险自然发生。").font(.system(size: 12)).lineSpacing(5).foregroundStyle(Theme.ink.opacity(0.7))
                Button { model.showCreate = true } label: { Label("创建游戏实例", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 6) }.buttonStyle(.borderedProminent).tint(Theme.ink).disabled(model.busy)
            }.padding(32)
        }.frame(height: 295).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func quickCard(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Surface {
                VStack(alignment: .leading, spacing: 11) {
                    HStack { Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(Theme.accent); Spacer(); Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary) }
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
    private func launchButton(_ instance: GameInstance) -> some View {
        Button { if model.runningID == instance.id { model.stopGame() } else { model.launch(instance) } } label: {
            Label(model.runningID == instance.id ? "结束游戏" : instance.installed ? "启动游戏" : "继续安装", systemImage: model.runningID == instance.id ? "stop.fill" : "play.fill").padding(.horizontal, 15).padding(.vertical, 9)
        }.buttonStyle(.borderedProminent).disabled(model.busy || (model.runningID != nil && model.runningID != instance.id))
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var deleteTarget: GameInstance?
    var filtered: [GameInstance] { model.state.instances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.gameVersion.contains(search) }.sorted { $0.favorite != $1.favorite ? $0.favorite : $0.createdAt > $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: "你的游戏收藏", subtitle: "每个实例都有独立的模组、存档和设置。")
                    Spacer(); Button("新建实例", systemImage: "plus") { model.showCreate = true }.buttonStyle(.borderedProminent).disabled(model.busy)
                }
                TextField("搜索实例或版本", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 330)
                if filtered.isEmpty {
                    EmptyPanel(symbol: "square.stack.3d.up", title: model.state.instances.isEmpty ? "第一个世界，等你开启" : "没有匹配的实例", detail: "创建一个游戏实例，或导入你喜爱的整合包。")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 18)], spacing: 18) {
                    ForEach(filtered) { instance in
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    InstanceIcon(loader: instance.loader)
                                    Spacer()
                                    if instance.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                                    Menu {
                                        Button("设为首页实例") { model.select(instance) }
                                        Button(instance.favorite ? "取消收藏" : "收藏") { var value = instance; value.favorite.toggle(); model.update(value) }
                                        Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
                                        Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
                                        Button("管理模组与资源包", systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
                                        Button("管理存档与备份", systemImage: "globe") { model.worldInstance = instance }
                                        Button("修复游戏文件") { model.repair(instance) }.disabled(model.busy || model.runningID == instance.id || !instance.installed)
                                        Divider()
                                        Button("移到废纸篓", role: .destructive) { deleteTarget = instance }.disabled(model.busy || model.runningID == instance.id)
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(instance.name).font(.headline).lineLimit(1)
                                    Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                HStack { TagPill(text: model.runningID == instance.id ? "运行中" : instance.installed ? "就绪" : "待安装"); Spacer(); Text("\(instance.memoryMB / 1024) GB").font(.caption).foregroundStyle(.secondary) }
                                Divider()
                                HStack {
                                    Button { model.editingInstance = instance } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).help("实例设置")
                                    Spacer()
                                    Button { model.select(instance); model.launch(instance) } label: { Label(instance.installed ? "启动" : "继续安装", systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(model.busy || model.runningID != nil)
                                }
                            }
                        }
                    }
                }
            }.padding(30)
        }
        .confirmationDialog("将实例移到废纸篓？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { if let target = deleteTarget { model.trash(target) }; deleteTarget = nil }
        } message: { Text("实例的存档和模组会一起移入废纸篓。共享游戏文件会保留。") }
    }
}
