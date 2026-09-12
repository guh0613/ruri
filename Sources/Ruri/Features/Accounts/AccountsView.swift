import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// Signed-in accounts as a grouped settings-style list.
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var relogin: Account?
    @State private var appearanceAccount: Account?
    var body: some View {
        Form {
            Section {
                if model.state.accounts.isEmpty {
                    Label(Messages.AppAccountsView.emptyState.localized, systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary).padding(.vertical, 4)
                }
                ForEach(model.state.accounts) { account in accountRow(account) }
            } header: {
                Text(Messages.AppAccountsView.account.localized)
            } footer: {
                Text(Messages.AppAccountsView.credentials.localized)
            }
        }
        .formStyle(.grouped)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { model.showAccount = true } label: { Label(Messages.AppAccountsView.addAccount.localized, systemImage: "plus") }.help(Messages.AppAccountsView.addAccount.localized).disabled(model.busy || model.readOnly) } }
        .sheet(item: $relogin) { ExternalAccountReloginView(account: $0) }
        .sheet(item: $appearanceAccount) { AccountAppearanceView(account: $0) }
    }
    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.square.fill").font(.system(size: 30)).foregroundStyle(Theme.accent).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.username).font(.headline)
                Text(account.kindLabel).font(.caption).foregroundStyle(.secondary)
                if let login = account.externalLogin { Text(login.server.url.absoluteString).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer()
            if model.state.activeAccountID == account.id { TagPill(text: Messages.AppAccountsView.currentAccount.localized) }
            else { Button(Messages.AppAccountsView.useAccount.localized) { model.state.activeAccountID = account.id; model.save() }.disabled(model.readOnly) }
            Menu {
                if account.kind != .offline { Button(Messages.AppAccountsView.appearance.localized, systemImage: "tshirt") { appearanceAccount = account } }
                if account.kind == .external {
                    Button(Messages.AppAccountsView.refreshLogin.localized, systemImage: "arrow.clockwise") { run { try await model.refreshExternal(account) } }
                    Button(Messages.AppAccountsView.relogin.localized, systemImage: "key") { relogin = account }
                    Button(Messages.AppAccountsView.removeLogin.localized, systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { run { try await model.logoutExternal(account) } }
                    Divider()
                }
                Button(Messages.AppAccountsView.removeFromRuri.localized, systemImage: "trash", role: .destructive) { model.removeAccount(account) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.busy || model.readOnly)
        }
        .padding(.vertical, 4)
    }
    private func run(_ operation: @escaping @MainActor @Sendable () async throws -> Void) {
        model.perform(Messages.AppAccountsView.updateAccount) { _ in try await operation() }
    }
}
