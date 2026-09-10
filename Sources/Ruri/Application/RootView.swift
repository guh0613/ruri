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
                DirectorySidebarPicker().padding(.horizontal, 16).padding(.bottom, 10)
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
                    HStack { Image(systemName: "info.circle"); Text(notice).font(.callout); Spacer(); if let id = model.noticeSessionID { Button("查看记录") { model.showSession(id) } }; if let url = model.noticeFileURL { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }; Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
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
                        if model.runningID != nil { Button { model.showSession(model.runningID.flatMap { model.activeSessions[$0]?.id }) } label: { Label("运行日志", systemImage: "terminal") } }
                        Button { model.showCreate = true } label: { Label("新建实例", systemImage: "plus") }.help("新建实例 ⌘N").disabled(model.busy)
                    }
                }
        }
        .tint(Theme.accent)
        .frame(minWidth: 760, minHeight: 600)
        .preferredColorScheme(model.colorScheme)
        .sheet(isPresented: $model.showCreate) { CreateInstanceView() }
        .sheet(isPresented: $model.showDirectories) { GameDirectoriesView() }
        .sheet(isPresented: $model.showAccount) { AddAccountView() }
        .sheet(isPresented: $model.showLogs) { LogsView() }
        .sheet(item: $model.editingInstance) { instance in InstanceSettingsView(instance: instance) }
        .sheet(item: $model.contentInstance) { instance in InstanceContentView(instance: instance) }
        .sheet(item: $model.worldInstance) { instance in WorldManagerView(instance: instance) }
        .sheet(item: $model.importingInstance) { prepared in ImportInstanceView(prepared: prepared) }
        .sheet(item: $model.minecraftDirectory) { catalog in MinecraftDirectoryView(catalog: catalog) }
        .sheet(item: $model.exportingInstance) { instance in ExportInstanceView(instance: instance) }
        .sheet(item: $model.copyingInstance) { instance in InstanceCopyView(instance: instance) }
        .sheet(item: $model.movingInstance) { instance in InstanceMoveView(instance: instance) }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好", role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .task { await model.boot() }
    }
    private func sidebarRow(_ page: Page) -> some View {
        Label(page.title, systemImage: page.symbol).font(.system(size: 13)).padding(.vertical, 5).tag(page)
    }
}
