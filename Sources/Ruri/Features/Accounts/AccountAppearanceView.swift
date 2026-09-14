import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

/// The appearance half of an account page: one card with the character on
/// the left and a skin row and a cape row on the right, followed by the skin
/// library. Picking a file or a saved skin opens a confirmation sheet, so the
/// card always shows what the account really has.
struct AccountAppearanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let account: Account
    var relogin: () -> Void = {}
    @State private var client: AccountAppearanceClient?
    @State private var appearance: AccountAppearance?
    @State private var skin: PlayerTextureImage?
    @State private var cape: PlayerTextureImage?
    @State private var capeID = ""
    @State private var draft: AppearanceDraft?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var capeError: String?
    @State private var message: String?
    @State private var messageTask: Task<Void, Never>?
    @State private var library: [SavedPlayerSkin] = []
    @State private var unreadableSkins = 0
    @State private var renameSkin: SavedPlayerSkin?
    @State private var renameText = ""
    @State private var removeSkin: SavedPlayerSkin?
    @State private var resetKind: PlayerTextureKind?
    @State private var revision = UUID()
    private var store: SkinLibrary { SkinLibrary(paths: model.paths) }
    private var isOffline: Bool { account.kind == .offline }
    private var selectedCape: AccountTexture? { appearance?.capes.first { $0.id == capeID } }
    private var skinModel: PlayerSkinModel { appearance?.skin?.model ?? model.accountSkins[account.id]?.model ?? .classic }
    private var skinName: String? {
        if isOffline { return model.accountSkins[account.id]?.name }
        return appearance?.playerName ?? (skin == nil ? nil : account.username)
    }
    private var canUpload: Set<PlayerTextureKind> { isOffline ? [.skin, .cape] : appearance?.uploadable ?? [] }
    private var locked: Bool { task != nil || model.readOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            appearanceSection
            librarySection
        }
        .onAppear {
            model.loadAccountPreview(account)
            skin = model.accountSkins[account.id].flatMap { try? $0.image }
            if isOffline {
                do { skin = try store.preview(for: account.id)?.image; cape = try store.cape(for: account.id) }
                catch { self.error = error.localizedDescription }
            }
            reloadLibrary()
            if !isOffline { load() }
        }
        .onDisappear { task?.cancel(); messageTask?.cancel() }
        .task(id: "\(revision)-\(capeID)") {
            if isOffline { return }
            cape = nil; capeError = nil
            guard let selectedCape, let client else { return }
            do {
                let image = try await client.image(for: selectedCape)
                try image.validate(kind: .cape, accountKind: account.kind)
                try Task.checkCancellation(); cape = image
            } catch { if !Task.isCancelled { capeError = error.localizedDescription } }
        }
        .sheet(item: $draft) { item in
            AppearanceDraftSheet(draft: item, account: account, currentSkin: skin, currentSkinModel: skinModel, currentCape: cape,
                                 canApply: canUpload.contains(item.kind), chooseAgain: { choose(item.kind) },
                                 saveToLibrary: { try store.save(name: $0.name, image: $0.image, model: $0.model); reloadLibrary() },
                                 apply: { try await apply($0) })
                .id(item.id)
        }
        .alert(Messages.AccountCenter.renameSkin.localized, isPresented: Binding(get: { renameSkin != nil }, set: { if !$0 { renameSkin = nil } })) {
            TextField(Messages.AccountCenter.skinName.localized, text: $renameText)
            Button(Messages.Common.cancel.localized, role: .cancel) { renameSkin = nil }
            Button(Messages.AccountCenter.save.localized) {
                guard let renameSkin else { return }
                localAction { try store.rename(renameSkin.id, to: renameText); reloadLibrary() }; self.renameSkin = nil
            }
        }
        .alert(Messages.AccountCenter.removeSkinTitle.localized, isPresented: Binding(get: { removeSkin != nil }, set: { if !$0 { removeSkin = nil } })) {
            Button(Messages.Common.cancel.localized, role: .cancel) { removeSkin = nil }
            Button(Messages.AccountCenter.removeSkin.localized, role: .destructive) {
                if let removeSkin { localAction { try store.remove(removeSkin.id); reloadLibrary() } }; removeSkin = nil
            }
        } message: { Text(Messages.AccountCenter.removeSkinHelp.localized) }
        .confirmationDialog(Messages.AccountCenter.resetAppearance.localized, isPresented: Binding(get: { resetKind != nil }, set: { if !$0 { resetKind = nil } }), titleVisibility: .visible) {
            Button(Messages.AccountCenter.confirmReset.localized, role: .destructive) {
                guard let kind = resetKind else { return }; resetKind = nil
                if isOffline {
                    localAction {
                        if kind == .skin { try model.cacheAccountSkin(nil, account: account); skin = nil }
                        else { try model.cacheAccountCape(nil, account: account); cape = nil }
                        show(Messages.AccountCenter.appearanceReset.localized)
                    }
                } else if let appearance {
                    change(Messages.AccountCenter.appearanceReset.localized) { try await $0.reset(kind, expecting: appearance) }
                }
            }
        }
    }

    // MARK: Appearance card

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppAccountAppearanceView.skinsAndCapes.localized) {
                if !isOffline {
                    HStack(spacing: 10) {
                        if task != nil { ProgressView().controlSize(.small).accessibilityLabel(Messages.AppAccountAppearanceView.processing.localized) }
                        Label(appearance != nil ? Messages.AccountCenter.connected.localized : task != nil ? Messages.AccountCenter.connecting.localized : Messages.AccountCenter.unverified.localized,
                              systemImage: appearance != nil ? "checkmark.shield.fill" : "network")
                            .foregroundStyle(.secondary)
                        Button { load() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .help(Messages.AppAccountAppearanceView.refresh.localized).accessibilityLabel(Messages.AppAccountAppearanceView.refresh.localized)
                            .disabled(locked)
                    }
                }
            }
            Surface(padding: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        preview.frame(width: 272)
                        Divider()
                        inspector.frame(minWidth: 360, maxWidth: .infinity).padding(22)
                    }.fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        preview
                        Divider()
                        inspector.padding(22)
                    }
                }
            }
            Text(isOffline ? Messages.AccountCenter.offlinePreviewHelp.localized
                 : account.kind == .microsoft ? Messages.AccountCenter.microsoftSkinHelp.localized
                 : Messages.AppAccountAppearanceView.appearanceChangesSaved.localized)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var preview: some View {
        PlayerSkinPreview(image: skin, model: skinModel, cape: cape, height: 320, framed: false)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            skinRow
            Divider().padding(.vertical, 18)
            capeRow
            if message != nil || error != nil {
                Divider().padding(.vertical, 18)
                feedback
            }
        }
    }

    private var skinRow: some View {
        AppearanceRow(label: Messages.AccountCenter.skinSection.localized,
                      title: skinName ?? (skin == nil ? Messages.AccountCenter.defaultSkin.localized : Messages.AppAccountAppearanceView.currentSkin.localized),
                      subtitle: skinSubtitle) {
            SkinAvatar(image: skin, size: 44)
        } controls: {
            if canUpload.contains(.skin) {
                Button(skin == nil ? Messages.AppAccountAppearanceView.chooseSkinPNG.localized : Messages.AccountCenter.replaceSkin.localized) { choose(.skin) }
            }
            Menu {
                Button(Messages.AccountCenter.saveToLibrary.localized, systemImage: "books.vertical") {
                    guard let skin else { return }
                    localAction {
                        try store.save(name: String((skinName ?? account.username).prefix(80)), image: skin, model: skinModel)
                        reloadLibrary(); show(Messages.AccountCenter.savedToLibrary.localized)
                    }
                }.disabled(skin == nil)
                Button(Messages.AppAccountAppearanceView.savePNG.localized, systemImage: "square.and.arrow.down") {
                    if let skin { savePNG(skin, name: skinName ?? account.username) }
                }.disabled(skin == nil)
                if canUpload.contains(.skin) {
                    Divider()
                    Button(Messages.AppAccountAppearanceView.restoreDefaultSkin.localized, systemImage: "arrow.uturn.backward", role: .destructive) { resetKind = .skin }
                        .disabled(skin == nil && appearance?.skin == nil)
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(Messages.AccountCenter.skinActions.localized).accessibilityLabel(Messages.AccountCenter.skinActions.localized)
        }
        .disabled(locked)
    }

    private var skinSubtitle: String {
        if !canUpload.contains(.skin), appearance != nil { return Messages.AppAccountAppearanceView.skinUploadUnavailable.localized }
        if let skin { return [skinModel.title, Messages.AccountCenter.textureSize(Int64(skin.width), Int64(skin.height)).localized].joined(separator: " · ") }
        if !isOffline, appearance == nil { return Messages.AccountCenter.appearanceUnavailableOffline.localized }
        return canUpload.contains(.skin) ? Messages.AccountCenter.chooseSkinHelp.localized : Messages.AccountCenter.defaultSkinHelp.localized
    }

    private var capeRow: some View {
        AppearanceRow(label: Messages.AccountCenter.capeSection.localized, title: capeTitle, subtitle: capeSubtitle) {
            CapeThumbnail(image: cape, size: 44)
        } controls: {
            if !isOffline && appearance == nil {
                EmptyView()
            } else if account.kind == .microsoft, let appearance {
                if !appearance.capes.isEmpty {
                    Picker(Messages.AppAccountAppearanceView.ownedCapes.localized, selection: $capeID) {
                        Text(Messages.AppAccountAppearanceView.hideCape.localized).tag("")
                        Divider()
                        ForEach(appearance.capes) { Text($0.name).tag($0.id) }
                    }.labelsHidden().fixedSize()
                    Button(Messages.AccountCenter.applyCape.localized) {
                        let id = capeID
                        change(Messages.AppAccountAppearanceView.capeChanged.localized) {
                            if id.isEmpty { try await $0.reset(.cape, expecting: appearance) }
                            else { try await $0.selectCape(id, expecting: appearance) }
                        }
                    }.disabled(capeID == (appearance.activeCape?.id ?? ""))
                }
                capeMenu(removable: false)
            } else if canUpload.contains(.cape) {
                Button(cape == nil ? Messages.AppAccountAppearanceView.chooseCapePNG.localized : Messages.AccountCenter.replaceSkin.localized) { choose(.cape) }
                capeMenu(removable: true)
            } else {
                capeMenu(removable: false)
            }
        }
        .disabled(locked)
    }

    private var capeTitle: String {
        if account.kind == .microsoft { return appearance?.activeCape?.name ?? Messages.AppAccountAppearanceView.noCapeInUse.localized }
        if !isOffline && appearance == nil { return Messages.AppAccountAppearanceView.cape.localized }
        return cape == nil && appearance?.activeCape == nil ? Messages.AppAccountAppearanceView.noCapeInUse.localized : Messages.CoreAccountAppearance.currentCape.localized
    }
    private var capeSubtitle: String {
        if let capeError { return capeError }
        if !isOffline && appearance == nil { return Messages.AccountCenter.appearanceNotLoaded.localized }
        if account.kind == .microsoft, appearance?.capes.isEmpty == true { return Messages.AppAccountAppearanceView.noCapeOwned.localized }
        if account.kind == .external, !canUpload.contains(.cape) { return Messages.AppAccountAppearanceView.capeUploadUnavailable.localized }
        if let cape { return Messages.AccountCenter.textureSize(Int64(cape.width), Int64(cape.height)).localized }
        return canUpload.contains(.cape) ? Messages.AccountCenter.chooseCapeHelp.localized : Messages.AppAccountAppearanceView.noCape.localized
    }
    private func capeMenu(removable: Bool) -> some View {
        Menu {
            Button(Messages.AppAccountAppearanceView.savePNG.localized, systemImage: "square.and.arrow.down") {
                if let cape { savePNG(cape, name: PlayerTextureKind.cape.rawValue) }
            }.disabled(cape == nil)
            if removable {
                Divider()
                Button(Messages.AppAccountAppearanceView.removeCurrentCape.localized, systemImage: "trash", role: .destructive) { resetKind = .cape }
                    .disabled(isOffline ? cape == nil : appearance?.activeCape == nil)
            }
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(Messages.AccountCenter.capeActions.localized).accessibilityLabel(Messages.AccountCenter.capeActions.localized)
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message {
                Label(message, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.secondary).transition(.opacity)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if appearance == nil && !isOffline {
                    HStack(spacing: 10) {
                        Button(Messages.AccountCenter.retry.localized) { load() }
                        Button(Messages.AppAccountsView.relogin.localized, action: relogin)
                    }.controlSize(.small).disabled(locked)
                }
            }
        }.animation(.snappy, value: message)
    }

    // MARK: Skin library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AccountCenter.skinLibrary.localized) {
                HStack(spacing: 14) {
                    if !library.isEmpty { Text(Messages.AccountCenter.skinCount(Int64(library.count)).localized).foregroundStyle(.secondary) }
                    Button(Messages.AccountCenter.importSkin.localized, systemImage: "square.and.arrow.down") { choose(.skin) }.disabled(model.readOnly)
                }
            }
            if unreadableSkins > 0 {
                HStack {
                    Label(Messages.AccountCenter.unreadableSkins(Int64(unreadableSkins)).localized, systemImage: "exclamationmark.triangle").font(.callout)
                    Spacer()
                    Button(Messages.AccountCenter.showSkinFolder.localized) { NSWorkspace.shared.open(store.directoryURL) }.controlSize(.small)
                }.foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if library.isEmpty {
                Surface(padding: 0) {
                    ContentUnavailableView {
                        Label(Messages.AccountCenter.libraryEmpty.localized, systemImage: "tshirt")
                    } description: {
                        Text(Messages.AccountCenter.libraryEmptyHelp.localized)
                    }.frame(maxWidth: .infinity).padding(.vertical, 26)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(library) { entry in
                        SkinLibraryTile(entry: entry, inUse: skin?.png == entry.png && skinModel == entry.model) {
                            localAction { draft = AppearanceDraft(image: try entry.image, kind: .skin, name: entry.name, model: entry.model) }
                        } rename: { renameText = entry.name; renameSkin = entry }
                          export: { localAction { savePNG(try entry.image, name: entry.name) } }
                          remove: { removeSkin = entry }
                    }
                }.disabled(model.readOnly)
            }
        }
    }

    // MARK: Actions

    private func choose(_ kind: PlayerTextureKind) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localAction {
            let image = try PlayerTextureImage.load(url)
            try image.validate(kind: kind, accountKind: .offline)
            draft = AppearanceDraft(image: image, kind: kind, name: String(url.deletingPathExtension().lastPathComponent.prefix(80)),
                                    model: image.isLegacySkin ? .classic : skinModel)
        }
    }
    private func apply(_ draft: AppearanceDraft) async throws {
        guard !model.readOnly else { return }
        if isOffline {
            if draft.kind == .skin {
                let saved = try SavedPlayerSkin(name: draft.name, image: draft.image, model: draft.model)
                try model.cacheAccountSkin(saved, account: account); skin = draft.image
            } else { try model.cacheAccountCape(draft.image, account: account); cape = draft.image }
            error = nil; show(Messages.AccountCenter.localPreviewSaved.localized)
            return
        }
        guard let appearance else { return }
        try await model.withAppearanceClient(for: account) { client in
            try await client.upload(draft.image, kind: draft.kind, model: draft.model, expecting: appearance)
            try Task.checkCancellation()
            error = nil; show(Messages.AppAccountAppearanceView.uploaded(draft.kind.title).localized)
            do { try await fetch(client) }
            catch { if !Task.isCancelled { self.error = Messages.AppAccountAppearanceView.refreshAppearanceError(error.localizedDescription).localized } }
        }
    }
    private func load() {
        guard task == nil, !model.readOnly else { return }
        error = nil
        task = Task {
            defer { task = nil }
            do { try await model.withAppearanceClient(for: account) { try await fetch($0) } }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func fetch(_ pendingClient: AccountAppearanceClient) async throws {
        let loaded = try await pendingClient.load()
        try Task.checkCancellation()
        client = pendingClient; appearance = loaded; capeID = loaded.activeCape?.id ?? ""; revision = UUID()
        if let texture = loaded.skin {
            let image = try await pendingClient.image(for: texture)
            try image.validate(kind: .skin, accountKind: account.kind, model: texture.model)
            try Task.checkCancellation()
            try model.cacheAccountSkin(SavedPlayerSkin(name: String(loaded.playerName.prefix(80)), image: image, model: texture.model), account: account)
            skin = image
        } else {
            try model.cacheAccountSkin(nil, account: account); skin = nil
        }
    }
    private func change(_ success: String, action: @escaping @MainActor (AccountAppearanceClient) async throws -> Void) {
        guard task == nil, !model.readOnly else { return }
        error = nil
        task = Task {
            defer { task = nil }
            do {
                try await model.withAppearanceClient(for: account) { client in
                    try Task.checkCancellation(); try await action(client)
                    try Task.checkCancellation(); show(success)
                    do { try await fetch(client) }
                    catch { if !Task.isCancelled { self.error = Messages.AppAccountAppearanceView.refreshAppearanceError(error.localizedDescription).localized } }
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func reloadLibrary() {
        do { let listing = try store.listing(); library = listing.skins; unreadableSkins = listing.unreadableIDs.count }
        catch { self.error = error.localizedDescription }
    }
    private func localAction(_ action: () throws -> Void) {
        guard !model.readOnly else { return }
        error = nil
        do { try action() } catch { self.error = error.localizedDescription }
    }
    /// Confirmations fade out on their own; errors stay until the next action.
    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { message = nil }
        }
    }
    private func savePNG(_ image: PlayerTextureImage, name: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = name + ".png"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { try image.png.write(to: file, options: .atomic) } catch { self.error = error.localizedDescription }
    }
}

/// One line of the appearance inspector: a thumbnail, a small category
/// label over the current value, and the controls for changing it.
private struct AppearanceRow<Thumbnail: View, Controls: View>: View {
    let label: String
    let title: String
    let subtitle: String
    @ViewBuilder var thumbnail: Thumbnail
    @ViewBuilder var controls: Controls
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(title).font(.headline).lineLimit(1).help(title)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { controls }.fixedSize()
        }
    }
}

/// A saved skin in the library grid. Clicking it previews the skin on the
/// account; the less common actions live under the hover menu and the
/// context menu.
private struct SkinLibraryTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: SavedPlayerSkin
    let inUse: Bool
    let use: () -> Void
    let rename: () -> Void
    let export: () -> Void
    let remove: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: use) {
            VStack(spacing: 12) {
                SkinAvatar(image: try? entry.image, size: 64)
                VStack(spacing: 3) {
                    Text(entry.name).font(.headline).lineLimit(1).help(entry.name)
                    Text(entry.model.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if inUse { TagPill(text: Messages.AppAccountAppearanceView.currentlyInUse.localized) }
            }
            .padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 18)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Messages.AccountCenter.previewAndUse.localized)
        .accessibilityLabel(entry.name).accessibilityHint(Messages.AccountCenter.previewAndUse.localized)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(Theme.surface(for: colorScheme))
                .overlay { shape.fill(.primary.opacity(hovering ? 0.045 : 0)) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, x: 0, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(inUse ? Theme.accent.opacity(0.6) : .primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Menu { actions } label: { Image(systemName: "ellipsis.circle").font(.body) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(8).opacity(hovering ? 1 : 0)
                .help(Messages.AccountCenter.skinActions.localized).accessibilityLabel(Messages.AccountCenter.skinActions.localized)
        }
        .contextMenu {
            Button(Messages.AccountCenter.previewAndUse.localized, systemImage: "person.crop.rectangle", action: use)
            Divider()
            actions
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
    @ViewBuilder private var actions: some View {
        Group {
            Button(Messages.AccountCenter.renameSkin.localized, systemImage: "pencil", action: rename)
            Button(Messages.AppAccountAppearanceView.savePNG.localized, systemImage: "square.and.arrow.down", action: export)
            Divider()
            Button(Messages.AccountCenter.removeSkin.localized, systemImage: "trash", role: .destructive, action: remove)
        }.labelStyle(.titleAndIcon)
    }
}
