import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct AccountAppearanceView: View {
    @Environment(AppModel.self) private var model
    let account: Account
    var relogin: () -> Void = {}
    @State private var client: AccountAppearanceClient?
    @State private var appearance: AccountAppearance?
    @State private var skin: PlayerTextureImage?
    @State private var cape: PlayerTextureImage?
    @State private var capeID = ""
    @State private var draft: PlayerTextureImage?
    @State private var draftKind = PlayerTextureKind.skin
    @State private var draftName = ""
    @State private var skinModel = PlayerSkinModel.classic
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var capeError: String?
    @State private var message: String?
    @State private var tab = "skin"
    @State private var library: [SavedPlayerSkin] = []
    @State private var unreadableSkins = 0
    @State private var renameSkin: SavedPlayerSkin?
    @State private var renameText = ""
    @State private var removeSkin: SavedPlayerSkin?
    @State private var resetKind: PlayerTextureKind?
    @State private var revision = UUID()
    private var store: SkinLibrary { SkinLibrary(paths: model.paths) }
    private var selectedCape: AccountTexture? { appearance?.capes.first { $0.id == capeID } }
    private var previewModel: PlayerSkinModel { draft != nil && draftKind == .skin ? skinModel : appearance?.skin?.model ?? model.accountSkins[account.id]?.model ?? .classic }
    private var canUpload: Bool { account.kind == .offline || appearance?.uploadable.contains(.skin) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(Messages.AppAccountAppearanceView.skinsAndCapes.localized).font(.title3.weight(.semibold))
                Spacer()
                if task != nil { ProgressView().controlSize(.small).accessibilityLabel(Messages.AppAccountAppearanceView.processing.localized) }
                if account.kind != .offline {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                        .help(Messages.AppAccountAppearanceView.refresh.localized).accessibilityLabel(Messages.AppAccountAppearanceView.refresh.localized)
                        .disabled(task != nil || draft != nil || model.readOnly)
                }
            }
            if account.kind != .offline {
                Label(appearance != nil ? Messages.AccountCenter.connected.localized : task != nil ? Messages.AccountCenter.connecting.localized : Messages.AccountCenter.unverified.localized,
                      systemImage: appearance != nil ? "checkmark.shield" : "network")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker(Messages.AccountCenter.appearanceSection.localized, selection: $tab) {
                Text(Messages.CorePlayerTextureImage.skinTitle.localized).tag("skin")
                Text(Messages.AppAccountAppearanceView.cape.localized).tag("cape")
                Text(Messages.AccountCenter.skinLibrary.localized).tag("library")
            }.pickerStyle(.segmented).labelsHidden().disabled(task != nil || draft != nil)

            if tab == "library" { libraryView }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        preview.frame(width: 215)
                        editor.frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        preview.frame(maxWidth: .infinity)
                        editor
                    }
                }
            }
            if let message {
                Label(message, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
            }
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    if appearance == nil && account.kind != .offline {
                        HStack {
                            Button(Messages.AccountCenter.retry.localized) { load() }
                            Button(Messages.AppAccountsView.relogin.localized, action: relogin)
                        }.disabled(task != nil || model.readOnly)
                    }
                }
            }
            Text(account.kind == .offline ? Messages.AccountCenter.offlinePreviewHelp.localized : Messages.AppAccountAppearanceView.appearanceChangesSaved.localized)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            model.loadAccountPreview(account)
            skin = model.accountSkins[account.id].flatMap { try? $0.image }
            if account.kind == .offline {
                do { skin = try store.preview(for: account.id)?.image; cape = try store.cape(for: account.id) }
                catch { self.error = error.localizedDescription }
            }
            reloadLibrary()
            if account.kind != .offline { load() }
        }
        .onDisappear { task?.cancel() }
        .task(id: "\(revision)-\(capeID)") {
            if account.kind == .offline { return }
            cape = nil; capeError = nil
            guard let selectedCape, let client else { return }
            do {
                let image = try await client.image(for: selectedCape)
                try image.validate(kind: .cape, accountKind: account.kind)
                try Task.checkCancellation(); cape = image
            } catch { if !Task.isCancelled { capeError = error.localizedDescription } }
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
                if account.kind == .offline {
                    localAction {
                        if kind == .skin { try model.cacheAccountSkin(nil, account: account); skin = nil }
                        else { try model.cacheAccountCape(nil, account: account); cape = nil }
                        message = Messages.AccountCenter.appearanceReset.localized
                    }
                } else if let appearance {
                    change(Messages.AccountCenter.appearanceReset.localized) { try await $0.reset(kind, expecting: appearance) }
                }
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 8) {
            PlayerSkinPreview(image: draftKind == .skin ? draft ?? skin : skin, model: previewModel, cape: draftKind == .cape ? draft ?? cape : cape)
            if let capeError { Text(capeError).font(.caption).foregroundStyle(.red) }
        }
        .padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private var editor: some View {
        if let draft { draftEditor(draft) }
        else if tab == "cape" { capeEditor }
        else { skinEditor }
    }
    private var skinEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Messages.AppAccountAppearanceView.currentSkin.localized).font(.headline)
            if let skin {
                Text(previewModel.title).foregroundStyle(.secondary)
                Text(Messages.AccountCenter.textureSize(Int64(skin.width), Int64(skin.height)).localized).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(Messages.AccountCenter.chooseSkinHelp.localized).font(.callout).foregroundStyle(.secondary)
            }
            Button(Messages.AppAccountAppearanceView.chooseSkinPNG.localized) { choose(.skin) }
                .buttonStyle(.borderedProminent)
            if let skin {
                Button(Messages.AccountCenter.saveToLibrary.localized) {
                    localAction {
                        try store.save(name: String(account.username.prefix(80)), image: skin, model: previewModel)
                        reloadLibrary(); message = Messages.AccountCenter.savedToLibrary.localized
                    }
                }
                Button(Messages.AppAccountAppearanceView.savePNG.localized) { savePNG(skin, name: account.username) }
            }
            if canUpload {
                Button(account.kind == .offline ? Messages.AccountCenter.clearLocalPreview.localized : Messages.AppAccountAppearanceView.restoreDefaultSkin.localized) { resetKind = .skin }
                    .disabled(skin == nil && appearance?.skin == nil)
            } else if appearance != nil {
                Text(Messages.AppAccountAppearanceView.skinUploadUnavailable.localized).font(.caption).foregroundStyle(.secondary)
            }
            if account.kind == .microsoft { Text(Messages.AccountCenter.microsoftSkinHelp.localized).font(.caption).foregroundStyle(.secondary) }
        }.disabled(task != nil || model.readOnly)
    }
    private var capeEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Messages.AppAccountAppearanceView.cape.localized).font(.headline)
            if account.kind == .offline {
                Button(Messages.AppAccountAppearanceView.chooseCapePNG.localized) { choose(.cape) }.buttonStyle(.borderedProminent)
                if let cape { Button(Messages.AppAccountAppearanceView.savePNG.localized) { savePNG(cape, name: "cape") } }
                Button(Messages.AppAccountAppearanceView.removeCurrentCape.localized) { resetKind = .cape }.disabled(cape == nil)
            } else if let appearance {
                if account.kind == .microsoft {
                    Picker(Messages.AppAccountAppearanceView.ownedCapes.localized, selection: $capeID) {
                        Text(Messages.AppAccountAppearanceView.hideCape.localized).tag("")
                        ForEach(appearance.capes) { Text($0.name).tag($0.id) }
                    }
                    if appearance.capes.isEmpty {
                        Text(Messages.AppAccountAppearanceView.noCapeOwned.localized).font(.callout).foregroundStyle(.secondary)
                    }
                    Button(Messages.AccountCenter.applyCape.localized) {
                        let id = capeID
                        change(Messages.AppAccountAppearanceView.capeChanged.localized) {
                            if id.isEmpty { try await $0.reset(.cape, expecting: appearance) }
                            else { try await $0.selectCape(id, expecting: appearance) }
                        }
                    }.buttonStyle(.borderedProminent).disabled(capeID == (appearance.activeCape?.id ?? ""))
                } else if appearance.uploadable.contains(.cape) {
                    Button(Messages.AppAccountAppearanceView.chooseCapePNG.localized) { choose(.cape) }.buttonStyle(.borderedProminent)
                    Button(Messages.AppAccountAppearanceView.removeCurrentCape.localized) { resetKind = .cape }.disabled(appearance.activeCape == nil)
                } else {
                    Text(Messages.AppAccountAppearanceView.capeUploadUnavailable.localized).font(.callout).foregroundStyle(.secondary)
                }
                if let cape { Button(Messages.AppAccountAppearanceView.savePNG.localized) { savePNG(cape, name: "cape") } }
            } else { Text(Messages.AccountCenter.appearanceNotLoaded.localized).foregroundStyle(.secondary) }
        }.disabled(task != nil || model.readOnly)
    }
    private func draftEditor(_ image: PlayerTextureImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Messages.AccountCenter.previewBeforeApply.localized).font(.headline)
            Text(Messages.AccountCenter.textureSize(Int64(image.width), Int64(image.height)).localized).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if draftKind == .skin {
                TextField(Messages.AccountCenter.skinName.localized, text: $draftName).textFieldStyle(.roundedBorder)
                Picker(Messages.AppAccountAppearanceView.skinModel.localized, selection: $skinModel) {
                    ForEach(PlayerSkinModel.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(image.isLegacySkin)
                if image.isLegacySkin { Text(Messages.AccountCenter.legacySkinHelp.localized).font(.caption).foregroundStyle(.secondary) }
                Button(Messages.AccountCenter.saveToLibrary.localized) {
                    localAction {
                        try store.save(name: draftName, image: image, model: skinModel)
                        reloadLibrary(); message = Messages.AccountCenter.savedToLibrary.localized
                    }
                }
            }
            Button(account.kind == .offline ? Messages.AccountCenter.useLocalPreview.localized : Messages.AppAccountAppearanceView.uploadToAccount.localized) { applyDraft(image) }
                .buttonStyle(.borderedProminent)
                .disabled(account.kind != .offline && appearance?.uploadable.contains(draftKind) != true)
            HStack {
                Button(Messages.AppAccountAppearanceView.chooseAgain.localized) { choose(draftKind) }
                Button(Messages.Common.cancel.localized) { draft = nil; error = nil; message = nil }
            }
        }.disabled(task != nil || model.readOnly)
    }
    private var libraryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Messages.AccountCenter.libraryHelp.localized).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.AccountCenter.importSkin.localized) { choose(.skin) }.disabled(model.readOnly)
            }
            if unreadableSkins > 0 {
                HStack {
                    Label(Messages.AccountCenter.unreadableSkins(Int64(unreadableSkins)).localized, systemImage: "exclamationmark.triangle").font(.caption)
                    Spacer()
                    Button(Messages.AccountCenter.showSkinFolder.localized) { NSWorkspace.shared.open(store.directoryURL) }
                }.foregroundStyle(.secondary)
            }
            if library.isEmpty {
                ContentUnavailableView {
                    Label(Messages.AccountCenter.libraryEmpty.localized, systemImage: "tshirt")
                } description: { Text(Messages.AccountCenter.libraryEmptyHelp.localized) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(library) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SkinAvatar(image: try? entry.image, size: 48)
                                Spacer()
                                Menu {
                                    Button(Messages.AccountCenter.renameSkin.localized) { renameText = entry.name; renameSkin = entry }
                                    Button(Messages.AppAccountAppearanceView.savePNG.localized) { localAction { savePNG(try entry.image, name: entry.name) } }
                                    Button(Messages.AccountCenter.removeSkin.localized, role: .destructive) { removeSkin = entry }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                    .help(Messages.AccountCenter.skinActions.localized).accessibilityLabel(Messages.AccountCenter.skinActions.localized)
                            }
                            Text(entry.name).font(.headline).lineLimit(1).help(entry.name)
                            Text(entry.model.title).font(.caption).foregroundStyle(.secondary)
                            Button(Messages.AccountCenter.previewAndUse.localized) {
                                localAction { draft = try entry.image; draftKind = .skin; skinModel = entry.model; draftName = entry.name; tab = "skin" }
                            }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.disabled(model.readOnly)
            }
        }
    }

    private func choose(_ kind: PlayerTextureKind) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localAction {
            let image = try PlayerTextureImage.load(url)
            try image.validate(kind: kind, accountKind: .offline)
            draft = image; draftKind = kind; draftName = String(url.deletingPathExtension().lastPathComponent.prefix(80))
            skinModel = image.isLegacySkin ? .classic : appearance?.skin?.model ?? .classic
            tab = kind.rawValue
        }
    }
    private func applyDraft(_ image: PlayerTextureImage) {
        if account.kind == .offline {
            localAction {
                if draftKind == .skin {
                    let saved = try SavedPlayerSkin(name: draftName, image: image, model: skinModel)
                    try model.cacheAccountSkin(saved, account: account); skin = image
                } else { try model.cacheAccountCape(image, account: account); cape = image }
                draft = nil; message = Messages.AccountCenter.localPreviewSaved.localized
            }
        } else if let appearance {
            let kind = draftKind, selectedModel = skinModel
            change(Messages.AppAccountAppearanceView.uploaded(kind.title).localized) { try await $0.upload(image, kind: kind, model: selectedModel, expecting: appearance) }
        }
    }
    private func load() {
        guard task == nil, !model.readOnly else { return }
        error = nil; message = nil
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
        error = nil; message = nil
        task = Task {
            defer { task = nil }
            do {
                try await model.withAppearanceClient(for: account) { client in
                    try Task.checkCancellation(); try await action(client)
                    try Task.checkCancellation(); draft = nil; message = success
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
        error = nil; message = nil
        do { try action() } catch { self.error = error.localizedDescription }
    }
    private func savePNG(_ image: PlayerTextureImage, name: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = name + ".png"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { try image.png.write(to: file, options: .atomic) } catch { self.error = error.localizedDescription }
    }
}
