import SwiftUI
import AppKit
import RuriCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.page) {
                Section { ForEach([Page.home, .library, .discover, .downloads]) { page in sidebarRow(page) } }
                Section("管理") { ForEach([Page.accounts, .java, .settings]) { page in sidebarRow(page) } }
            }
            .listStyle(.sidebar)
            .controlSize(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) { AccountSidebarFooter() }
            .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice { NoticeBar(notice: notice) }
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
            }
                .background { Color(nsColor: .windowBackgroundColor).ignoresSafeArea(edges: .top) }
                .overlay(alignment: .top) { Divider() }
                .navigationTitle(model.page.title)
                .toolbar {
                    if let runningID = model.runningID {
                        ToolbarItem(placement: .primaryAction) {
                            Button { model.showSession(model.activeSessions[runningID]?.id) } label: { Label("运行记录", systemImage: "terminal") }
                                .help("查看正在运行的游戏的记录 ⌘L")
                        }
                    }
                }
        }
        .background(TransparentWindowTitlebar().allowsHitTesting(false))
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
        .sheet(item: $model.schematicInstance) { instance in SchematicManagerView(instance: instance) }
        .sheet(item: $model.importingInstance) { prepared in ImportInstanceView(prepared: prepared) }
        .sheet(item: $model.exportingInstance) { instance in ExportInstanceView(instance: instance) }
        .sheet(item: $model.copyingInstance) { instance in InstanceCopyView(instance: instance) }
        .sheet(item: $model.movingInstance) { instance in InstanceMoveView(instance: instance) }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好", role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .task { await model.boot() }
    }
    private func sidebarRow(_ page: Page) -> some View {
        HStack {
            Label(page.title, systemImage: page.symbol)
            Spacer()
            if page == .downloads, let task = model.activeActivity {
                if task.progress.total > 0 { ProgressView(value: task.progress.fraction).progressViewStyle(.circular).controlSize(.mini) }
                else { ProgressView().controlSize(.mini) }
            }
        }.padding(.vertical, 3).tag(page)
    }
}

/// The signed-in player, shown at the bottom of the sidebar like the account
/// entry in the App Store. The menu switches accounts without leaving the page.
private struct AccountSidebarFooter: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Menu {
                ForEach(model.state.accounts) { account in
                    Button { model.state.activeAccountID = account.id; model.save() } label: {
                        if account.id == model.state.activeAccountID { Label(account.username, systemImage: "checkmark") } else { Text(account.username) }
                    }
                }
                if !model.state.accounts.isEmpty { Divider() }
                Button("添加账号…") { model.showAccount = true }
                Button("管理账号…") { model.page = .accounts }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.activeAccount == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.fill")
                        .font(.system(size: 30)).symbolRenderingMode(.hierarchical).foregroundStyle(model.activeAccount == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.activeAccount?.username ?? "未登录").font(.system(size: 13, weight: .semibold))
                        Text(model.activeAccount?.kindLabel ?? "添加账号后即可启动游戏").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(model.readOnly)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .help(model.activeAccount == nil ? "添加账号" : "切换账号")
        }
    }
}

private struct NoticeBar: View {
    @Environment(AppModel.self) private var model
    let notice: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Theme.accent)
            Text(notice).font(.callout).lineLimit(2)
            Spacer()
            if let id = model.noticeSessionID { Button("查看记录") { model.showSession(id) } }
            if let url = model.noticeFileURL { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
