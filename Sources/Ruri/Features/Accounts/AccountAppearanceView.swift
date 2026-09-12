import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct AccountAppearanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var client: AccountAppearanceClient?
    @State private var appearance: AccountAppearance?
    @State private var capeID = ""
    @State private var draft: PlayerTextureImage?
    @State private var draftKind = PlayerTextureKind.skin
    @State private var skinModel = PlayerSkinModel.classic
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var message: String?
    @State private var previewRevision = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: Messages.AppAccountAppearanceView.bodyText1.localized, subtitle: "\(appearance?.playerName ?? account.username) · \(account.kindLabel)")
            if let login = account.externalLogin { Text(login.server.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let draft {
                        uploadEditor(draft)
                    } else if let appearance, let client {
                        HStack(alignment: .top, spacing: 18) {
                            GroupBox(Messages.AppAccountAppearanceView.clientText1.localized) {
                                VStack(spacing: 12) {
                                    AccountTexturePreview(texture: appearance.skin, kind: .skin, client: client)
                                    if let skin = appearance.skin { Text(skin.model.title).font(.caption).foregroundStyle(.secondary) }
                                    if appearance.uploadable.contains(.skin) {
                                        Button(Messages.AppAccountAppearanceView.skinText1.localized) { choose(.skin) }
                                        Button(Messages.AppAccountAppearanceView.skinText2.localized) { change(Messages.AppAccountAppearanceView.skinText3.localized) { try await $0.reset(.skin, expecting: appearance) } }
                                    } else { Text(Messages.AppAccountAppearanceView.skinText4.localized).font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity).padding(10)
                            }
                            GroupBox(Messages.AppAccountAppearanceView.skinText5.localized) {
                                VStack(spacing: 12) {
                                    if account.kind == .microsoft {
                                        Picker(Messages.AppAccountAppearanceView.skinText6.localized, selection: $capeID) {
                                            Text(Messages.AppAccountAppearanceView.skinText7.localized).tag("")
                                            ForEach(appearance.capes) { cape in Text(cape.name).tag(cape.id) }
                                        }
                                    }
                                    AccountTexturePreview(texture: account.kind == .microsoft ? appearance.capes.first { $0.id == capeID } : appearance.activeCape, kind: .cape, client: client)
                                    if account.kind == .microsoft {
                                        if capeID != (appearance.activeCape?.id ?? "") {
                                            Button(capeID.isEmpty ? Messages.AppAccountAppearanceView.skinText8.localized : Messages.AppAccountAppearanceView.skinText9.localized) {
                                                let selected = capeID
                                                change(selected.isEmpty ? Messages.AppAccountAppearanceView.selectedText1.localized : Messages.AppAccountAppearanceView.selectedText2.localized) {
                                                    if selected.isEmpty { try await $0.reset(.cape, expecting: appearance) }
                                                    else { try await $0.selectCape(selected, expecting: appearance) }
                                                }
                                            }
                                        } else { Text(capeID.isEmpty ? Messages.AppAccountAppearanceView.selectedText3.localized : Messages.AppAccountAppearanceView.selectedText4.localized).font(.caption).foregroundStyle(.secondary) }
                                        if appearance.capes.isEmpty { Text(Messages.AppAccountAppearanceView.selectedText5.localized).font(.caption).foregroundStyle(.secondary) }
                                    } else if appearance.uploadable.contains(.cape) {
                                        Button(Messages.AppAccountAppearanceView.selectedText6.localized) { choose(.cape) }
                                        Button(Messages.AppAccountAppearanceView.selectedText7.localized) { change(Messages.AppAccountAppearanceView.selectedText8.localized) { try await $0.reset(.cape, expecting: appearance) } }.disabled(appearance.activeCape == nil)
                                    } else { Text(Messages.AppAccountAppearanceView.selectedText9.localized).font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity).padding(10)
                            }
                        }.id(previewRevision).disabled(task != nil)
                        Text(Messages.AppAccountAppearanceView.selectedText10.localized).font(.caption).foregroundStyle(.secondary)
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if task != nil { ProgressView(Messages.AppAccountAppearanceView.errorText1.localized).controlSize(.small) }
                Spacer()
                Button(Messages.AppAccountAppearanceView.errorText2.localized) { load() }.disabled(task != nil || draft != nil)
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).disabled(task != nil)
            }
        }.padding(26).frame(width: 680, height: 570).onAppear { load() }.onDisappear { task?.cancel() }
    }

    private func uploadEditor(_ image: PlayerTextureImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Messages.AppAccountAppearanceView.uploadEditorText1(String(describing: draftKind.title)).localized).font(.headline)
            TexturePixels(image: image).frame(maxWidth: .infinity)
            Text("\(image.width) × \(image.height) PNG").font(.caption).foregroundStyle(.secondary)
            if draftKind == .skin {
                Picker(Messages.AppAccountAppearanceView.uploadEditorText2.localized, selection: $skinModel) { ForEach(PlayerSkinModel.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .disabled(image.isLegacySkin)
            }
            HStack {
                Button(Messages.AppAccountAppearanceView.uploadEditorText3.localized) { choose(draftKind) }
                Button(Messages.Common.cancel.localized) { draft = nil; error = nil }
                Spacer()
                Button(Messages.AppAccountAppearanceView.uploadEditorText4.localized) {
                    guard let appearance else { return }
                    let kind = draftKind, selectedModel = skinModel
                    change(Messages.AppAccountAppearanceView.kindText1(String(describing: kind.title)).localized) { try await $0.upload(image, kind: kind, model: selectedModel, expecting: appearance) }
                }.buttonStyle(.borderedProminent)
            }
        }.disabled(task != nil)
    }
    private func choose(_ kind: PlayerTextureKind) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let image = try PlayerTextureImage.load(url)
            try image.validate(kind: kind, accountKind: account.kind)
            draft = image; draftKind = kind
            skinModel = image.isLegacySkin ? .classic : appearance?.skin?.model ?? .classic
            error = nil; message = nil
        } catch { self.error = error.localizedDescription }
    }
    private func load() {
        error = nil; message = nil
        task = Task {
            defer { task = nil }
            do {
                let client = try await model.appearanceClient(for: account)
                let loaded = try await client.load()
                try Task.checkCancellation()
                self.client = client; appearance = loaded; capeID = loaded.activeCape?.id ?? ""; previewRevision = UUID()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func change(_ success: String, action: @escaping @MainActor (AccountAppearanceClient) async throws -> Void) {
        error = nil; message = nil
        task = Task {
            defer { task = nil }
            do {
                let client = try await model.appearanceClient(for: account)
                try Task.checkCancellation()
                try await action(client)
                draft = nil; message = success + "。"; self.client = client
                do {
                    let loaded = try await client.load()
                    appearance = loaded; capeID = loaded.activeCape?.id ?? ""; previewRevision = UUID()
                } catch { self.error = Messages.AppAccountAppearanceView.refreshAppearanceError(error.localizedDescription).localized }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct TexturePixels: View {
    let image: PlayerTextureImage
    var body: some View {
        if let native = NSImage(data: image.png) {
            Image(nsImage: native).resizable().interpolation(.none).scaledToFit().frame(height: 180)
                .padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(Messages.AppAccountAppearanceView.nativeText1.localized)
        }
    }
}

private struct AccountTexturePreview: View {
    let texture: AccountTexture?
    let kind: PlayerTextureKind
    let client: AccountAppearanceClient
    @State private var image: PlayerTextureImage?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 8) {
            if let image {
                TexturePixels(image: image)
                Text(Messages.AppAccountAppearanceView.imageText1.localized).font(.caption2).foregroundStyle(.secondary)
                Button(Messages.AppAccountAppearanceView.imageText2.localized) { save(image) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            else if let error { Text(error).font(.caption).foregroundStyle(.secondary).frame(height: 180) }
            else if texture != nil { ProgressView().frame(height: 180) }
            else { Label(kind == .skin ? Messages.AppAccountAppearanceView.errorText3.localized : Messages.AppAccountAppearanceView.errorText4.localized, systemImage: "person.crop.square").foregroundStyle(.secondary).frame(height: 180) }
        }.task(id: texture?.url) {
            image = nil; error = nil
            guard let texture else { return }
            do { let value = try await client.image(for: texture); try Task.checkCancellation(); image = value }
            catch { if !Task.isCancelled { self.error = Messages.AppAccountAppearanceView.appearanceError(error.localizedDescription).localized } }
        }
    }
    private func save(_ image: PlayerTextureImage) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = kind.rawValue + ".png"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { try image.png.write(to: file, options: .atomic) } catch { self.error = error.localizedDescription }
    }
}
