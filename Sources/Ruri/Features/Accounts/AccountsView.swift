import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

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
                    accountList.frame(minWidth: 190, idealWidth: 220, maxWidth: 290)
                    Group {
                        if let selected {
                            AccountDetailView(account: selected, relogin: { relogin = selected }, remove: { removing = selected }, logout: { loggingOut = selected }).id("\(selected.id)-\(detailRevision)")
                        } else {
                            ContentUnavailableView(Messages.AccountCenter.selectAccount.localized, systemImage: "person.crop.circle")
                        }
                    }.frame(minWidth: 330, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
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
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(accounts) { account in
                    HStack(spacing: 10) {
                        AccountAvatar(account: account)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.username).font(.body.weight(.medium)).lineLimit(1)
                            Text(account.kindLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        if model.state.activeAccountID == account.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                .help(Messages.AppAccountsView.currentAccount.localized).accessibilityLabel(Messages.AppAccountsView.currentAccount.localized)
                        }
                    }.padding(.vertical, 6).tag(account.id)
                    .contextMenu {
                        Button(Messages.AppAccountsView.useAccount.localized) { model.activateAccount(account) }
                        Divider()
                        Button(Messages.AppAccountsView.removeFromRuri.localized, role: .destructive) { removing = account }
                    }.disabled(model.readOnly)
                }
            }.listStyle(.inset)
                .overlay { if accounts.isEmpty { ContentUnavailableView.search(text: query) } }
                .onDeleteCommand { if !model.busy && !model.readOnly { removing = selected } }
            Divider()
            Text(Messages.AccountCenter.accountCount(Int64(model.state.accounts.count)).localized)
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(12)
        }
    }
    private func reconcileSelection() {
        if selected == nil { selectedID = model.activeAccount?.id ?? model.state.accounts.first?.id }
    }
}

private struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    let account: Account
    let relogin: () -> Void
    let remove: () -> Void
    let logout: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 16) {
                    AccountAvatar(account: account, size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(account.username).font(.title.weight(.bold)).textSelection(.enabled)
                        Text(account.kindLabel).foregroundStyle(.secondary)
                        if model.activeAccount?.id == account.id {
                            Label(Messages.AppAccountsView.currentAccount.localized, systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        if account.kind != .offline {
                            Button(Messages.AppAccountsView.relogin.localized, systemImage: "key", action: relogin)
                            Button(Messages.AppAccountsView.refreshLogin.localized, systemImage: "arrow.clockwise") {
                                model.perform(Messages.AppAccountsView.updateAccount) { _ in try await model.refreshAccount(account) }
                            }
                            Divider()
                        }
                        if account.kind == .external {
                            Button(Messages.AppAccountsView.removeLogin.localized, systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: logout)
                        }
                        Button(Messages.AccountCenter.copyUUID.localized, systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(account.uuid, forType: .string)
                        }
                        Button(Messages.AppAccountsView.removeFromRuri.localized, systemImage: "trash", role: .destructive, action: remove)
                    } label: { Label(Messages.AccountCenter.accountActions.localized, systemImage: "ellipsis.circle") }
                        .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(model.busy || model.readOnly)
                }
                if model.activeAccount?.id != account.id {
                    Button(Messages.AppAccountsView.useAccount.localized) { model.activateAccount(account) }
                        .buttonStyle(.borderedProminent).disabled(model.readOnly)
                }
                AccountAppearanceView(account: account, relogin: relogin)
                DisclosureGroup(Messages.AccountCenter.accountDetails.localized) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("UUID") { Text(account.uuid).font(.caption.monospaced()).textSelection(.enabled) }
                        if let login = account.externalLogin {
                            LabeledContent(Messages.AppExternalAccountForm.authServer.localized) { Text(login.server.url.absoluteString).textSelection(.enabled) }
                        }
                        Text(Messages.AppAccountsView.credentials.localized).font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }.font(.callout)
            }.padding(24).frame(maxWidth: 880, alignment: .leading).frame(maxWidth: .infinity)
        }.background(.background)
    }
}
