import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// Accounts as a master–detail page: the list on the left, and on the right
/// the selected player's identity card, appearance and details.
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var relogin: Account?
    @State private var removing: Account?
    @State private var loggingOut: Account?
    @State private var detailRevision = UUID()
    private var selected: Account? { model.state.accounts.first { $0.id == selectedID } }
    private var accounts: [Account] {
        model.state.accounts.filter { query.isEmpty || $0.username.localizedStandardContains(query) || $0.kindLabel.localizedStandardContains(query) }
    }
    var body: some View {
        Group {
            if model.state.accounts.isEmpty {
                ContentUnavailableView {
                    Label(Messages.AccountCenter.welcome.localized, systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text(Messages.AccountCenter.welcomeHelp.localized)
                } actions: {
                    Button(Messages.AppAccountsView.addAccount.localized) { model.showAccount = true }.buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.readOnly)
                }
            } else {
                HSplitView {
                    accountList.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    Group {
                        if let selected {
                            AccountDetailView(account: selected, relogin: { relogin = selected }, remove: { removing = selected }, logout: { loggingOut = selected }).id("\(selected.id)-\(detailRevision)")
                        } else {
                            ContentUnavailableView(Messages.AccountCenter.selectAccount.localized, systemImage: "person.crop.circle")
                        }
                    }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSubtitle(model.state.accounts.isEmpty ? "" : Messages.AccountCenter.accountCount(Int64(model.state.accounts.count)).localized)
        .searchable(text: $query, placement: .toolbar, prompt: Messages.AccountCenter.searchAccounts.localized)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.showAccount = true } label: { Label(Messages.AppAccountsView.addAccount.localized, systemImage: "plus") }
                    .help(Messages.AppAccountsView.addAccount.localized).disabled(model.busy || model.readOnly)
            }
        }
        .sheet(item: $relogin, onDismiss: { detailRevision = UUID() }) { account in
            if account.kind == .external { ExternalAccountReloginView(account: account) }
            else { AddAccountView(existing: account) }
        }
        .alert(Messages.AccountCenter.removeAccountTitle(removing?.username ?? "").localized, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(Messages.Common.cancel.localized, role: .cancel) { removing = nil }
            Button(Messages.AppAccountsView.removeFromRuri.localized, role: .destructive) {
                if let removing { model.removeAccount(removing) }; removing = nil
            }
        } message: { Text(Messages.AccountCenter.removeAccountHelp.localized) }
        .alert(Messages.AccountCenter.logoutTitle.localized, isPresented: Binding(get: { loggingOut != nil }, set: { if !$0 { loggingOut = nil } })) {
            Button(Messages.Common.cancel.localized, role: .cancel) { loggingOut = nil }
            Button(Messages.AppAccountsView.removeLogin.localized, role: .destructive) {
                if let account = loggingOut {
                    model.perform(Messages.AppAccountsView.updateAccount) { _ in try await model.logoutExternal(account) }
                }
                loggingOut = nil
            }
        } message: { Text(Messages.AccountCenter.logoutHelp.localized) }
        .onAppear { reconcileSelection() }
        .onChange(of: model.state.accounts.map(\.id)) { reconcileSelection() }
    }
    private var accountList: some View {
        List(selection: $selectedID) {
            ForEach(accounts) { account in
                HStack(spacing: 12) {
                    AccountAvatar(account: account, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.username).font(.body.weight(.medium)).lineLimit(1)
                        Text(account.kindLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    if model.state.activeAccountID == account.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            .help(Messages.AppAccountsView.currentAccount.localized).accessibilityLabel(Messages.AppAccountsView.currentAccount.localized)
                    }
                }.padding(.vertical, 5).tag(account.id)
                .contextMenu {
                    Button(Messages.AppAccountsView.useAccount.localized) { model.activateAccount(account) }.disabled(model.state.activeAccountID == account.id)
                    Divider()
                    Button(Messages.AppAccountsView.removeFromRuri.localized, role: .destructive) { removing = account }
                }.disabled(model.readOnly)
            }
        }.listStyle(.inset)
            .overlay { if accounts.isEmpty { ContentUnavailableView.search(text: query) } }
            .onDeleteCommand { if !model.busy && !model.readOnly { removing = selected } }
    }
    private func reconcileSelection() {
        if selected == nil { selectedID = model.activeAccount?.id ?? model.state.accounts.first?.id }
    }
}

private struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let account: Account
    let relogin: () -> Void
    let remove: () -> Void
    let logout: () -> Void
    private var isActive: Bool { model.activeAccount?.id == account.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                identityCard
                AccountAppearanceView(account: account, relogin: relogin)
                detailsSection
            }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.canvas(for: colorScheme))
    }

    private var identityCard: some View {
        Surface(padding: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    identity
                    Spacer(minLength: 20)
                    actions
                }
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    actions
                }
            }
        }
    }
    private var identity: some View {
        HStack(spacing: 18) {
            AccountAvatar(account: account, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(account.username).font(.system(size: 26, weight: .semibold)).textSelection(.enabled).lineLimit(1)
                HStack(spacing: 10) {
                    Text(account.kindLabel).font(.callout).foregroundStyle(.secondary)
                    if isActive { TagPill(text: Messages.AppAccountsView.currentAccount.localized) }
                }
            }
        }
    }
    private var actions: some View {
        HStack(spacing: 12) {
            if !isActive {
                Button(Messages.AppAccountsView.useAccount.localized) { model.activateAccount(account) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.readOnly)
            }
            Menu {
                Group {
                    if account.kind != .offline {
                        Button(Messages.AppAccountsView.relogin.localized, systemImage: "key", action: relogin)
                        Button(Messages.AppAccountsView.refreshLogin.localized, systemImage: "arrow.clockwise") {
                            model.perform(Messages.AppAccountsView.updateAccount) { _ in try await model.refreshAccount(account) }
                        }
                        Divider()
                    }
                    Button(Messages.AccountCenter.copyUUID.localized, systemImage: "doc.on.doc") { copyUUID() }
                    Divider()
                    if account.kind == .external {
                        Button(Messages.AppAccountsView.removeLogin.localized, systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: logout)
                    }
                    Button(Messages.AppAccountsView.removeFromRuri.localized, systemImage: "trash", role: .destructive, action: remove)
                }.labelStyle(.titleAndIcon)
            } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(Messages.AccountCenter.accountActions.localized).accessibilityLabel(Messages.AccountCenter.accountActions.localized)
                .disabled(model.busy || model.readOnly)
        }.fixedSize()
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AccountCenter.accountDetails.localized)
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    detailRow(Messages.AccountCenter.accountType.localized) { Text(account.kindLabel) }
                    Divider().padding(.leading, 20)
                    detailRow("UUID") {
                        Text(account.uuid).font(.body.monospaced()).textSelection(.enabled)
                    } trailing: {
                        Button { copyUUID() } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help(Messages.AccountCenter.copyUUID.localized).accessibilityLabel(Messages.AccountCenter.copyUUID.localized)
                    }
                    if let login = account.externalLogin {
                        Divider().padding(.leading, 20)
                        detailRow(Messages.AppExternalAccountForm.authServer.localized) {
                            Text(login.server.url.absoluteString).textSelection(.enabled)
                        }
                    }
                }
            }
            Text(Messages.AppAccountsView.credentials.localized).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func detailRow<Value: View, Trailing: View>(_ label: String, @ViewBuilder value: () -> Value, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            value().lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            trailing()
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }
    private func detailRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        detailRow(label, value: value) { EmptyView() }
    }
    private func copyUUID() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(account.uuid, forType: .string)
    }
}
