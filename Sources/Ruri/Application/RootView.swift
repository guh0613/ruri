import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columns = NavigationSplitViewVisibility.automatic
    var body: some View {
        // The library is a list with a detail beside it, so it adds a content
        // column like Mail; every other page is a single detail.
        ZStack {
            if model.page == .library {
                LibraryView(columnVisibility: $columns) { RootSidebar() }
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    RootSidebar()
                } detail: {
                    Group {
                        switch model.page {
                        case .home, .library: HomeView()
                        case .discover: DiscoverView()
                        case .activity: LauncherLogView().id(model.logNavigationID)
                        case .accounts: AccountsView()
                        case .java: JavaView()
                        case .settings: PreferencesView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(model.page.title)
                    .toolbar { RootToolbar(model: model) }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 600)
        .preferredColorScheme(model.colorScheme)
        .sheet(isPresented: Bindable(model).showCreate) { CreateInstanceView() }
        .sheet(isPresented: Bindable(model).showDirectories) { GameDirectoriesView() }
        .sheet(isPresented: Bindable(model).showAccount) { AddAccountView() }
        .sheet(isPresented: Bindable(model).showLogs) { LogsView() }
        .sheet(item: Bindable(model).editingInstance) { instance in InstanceSettingsView(instance: instance) }
        .sheet(item: Bindable(model).contentInstance, onDismiss: { model.contentKind = .mod }) { instance in InstanceContentView(instance: instance, kind: model.contentKind) }
        .sheet(item: Bindable(model).worldInstance) { instance in WorldManagerView(instance: instance) }
        .sheet(item: Bindable(model).schematicInstance) { instance in SchematicManagerView(instance: instance) }
        .sheet(item: Bindable(model).importingInstance) { prepared in ImportInstanceView(prepared: prepared) }
        .sheet(item: Bindable(model).exportingInstance) { instance in ExportInstanceView(instance: instance) }
        .sheet(item: Bindable(model).copyingInstance) { instance in InstanceCopyView(instance: instance) }
        .sheet(item: Bindable(model).movingInstance) { instance in InstanceMoveView(instance: instance) }
        .alert(Messages.AppRootView.operationIncomplete.localized, isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(Messages.AppRootView.ok.localized, role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .task { await model.boot() }
    }
}

/// App-wide items at the trailing edge of the detail column's toolbar.
struct RootToolbar: ToolbarContent {
    let model: AppModel
    var body: some ToolbarContent {
        // In the library's detail column nothing else fills the toolbar, so
        // without a spacer these items sit at its leading edge.
        if #available(macOS 26, *) { ToolbarSpacer(.flexible, placement: .primaryAction) }
        ToolbarItem(placement: .primaryAction) { LauncherNotificationButton() }
        if let runningID = model.runningID {
            ToolbarItem(placement: .primaryAction) {
                Button { model.showSession(model.activeSessions[runningID]?.id) } label: { Label(Messages.AppRootView.runHistory.localized, systemImage: "terminal") }
                    .help(Messages.AppRootView.viewRunningGameLogs.localized)
            }
        }
    }
}

private struct RootSidebar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        List(selection: $model.page) {
            Section { ForEach([Page.home, .library, .discover, .activity]) { page in sidebarRow(page) } }
            Section(Messages.AppRootView.manage.localized) { ForEach([Page.accounts, .java, .settings]) { page in sidebarRow(page) } }
        }
        .listStyle(.sidebar)
        .controlSize(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) { AccountSidebarFooter() }
        .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 320)
    }
    private func sidebarRow(_ page: Page) -> some View {
        HStack {
            Label(page.title, systemImage: page.symbol)
            Spacer()
            if page == .activity, let task = model.activeActivity {
                if task.progress.total > 0 { ProgressView(value: task.progress.fraction).progressViewStyle(.circular).controlSize(.mini) }
                else { ProgressView().controlSize(.mini) }
            } else if page == .activity, model.journal.unreadCount > 0 {
                Text(model.journal.unreadCount, format: .number).font(.caption).foregroundStyle(.secondary)
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
                Group {
                    if !model.state.accounts.isEmpty {
                        Picker(Messages.AppRootView.switchAccount.localized, selection: Binding(get: { model.state.activeAccountID }, set: { id in
                            guard id != model.state.activeAccountID else { return }
                            if let account = model.state.accounts.first(where: { $0.id == id }) { model.activateAccount(account) }
                        })) {
                            ForEach(model.state.accounts) { account in
                                Text(account.username).tag(Optional(account.id))
                            }
                        }.pickerStyle(.inline).labelsHidden()
                        Divider()
                    }
                    Button(Messages.AppRootView.addAccount.localized, systemImage: "person.badge.plus") { model.showAccount = true }
                    Button(Messages.AppRootView.manageAccounts.localized, systemImage: "person.2") { model.page = .accounts }
                }.labelStyle(.titleAndIcon)
            } label: {
                HStack(spacing: 10) {
                    if let account = model.activeAccount { AccountAvatar(account: account, size: 32) }
                    else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.activeAccount?.username ?? Messages.AppRootView.notSignedIn.localized).font(.system(size: 13, weight: .semibold))
                        Text(model.activeAccount?.kindLabel ?? Messages.AppRootView.addAccountToLaunch.localized).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .labelStyle(.titleAndIcon)
            .disabled(model.readOnly)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .help(model.activeAccount == nil ? Messages.AppRootView.addAnotherAccount.localized : Messages.AppRootView.switchAccount.localized)
        }
    }
}
