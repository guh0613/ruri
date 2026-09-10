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
            SectionHeading(title: "皮肤与披风", subtitle: "\(appearance?.playerName ?? account.username) · \(account.kindLabel)")
            if let login = account.externalLogin { Text(login.server.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let draft {
                        uploadEditor(draft)
                    } else if let appearance, let client {
                        HStack(alignment: .top, spacing: 18) {
                            GroupBox("当前皮肤") {
                                VStack(spacing: 12) {
                                    AccountTexturePreview(texture: appearance.skin, kind: .skin, client: client)
                                    if let skin = appearance.skin { Text(skin.model.title).font(.caption).foregroundStyle(.secondary) }
                                    if appearance.uploadable.contains(.skin) {
                                        Button("选择皮肤 PNG…") { choose(.skin) }
                                        Button("恢复默认皮肤") { change("已恢复默认皮肤") { try await $0.reset(.skin, expecting: appearance) } }
                                    } else { Text("此认证站未开放皮肤上传，请在认证站管理。").font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity).padding(10)
                            }
                            GroupBox("披风") {
                                VStack(spacing: 12) {
                                    if account.kind == .microsoft {
                                        Picker("已拥有的披风", selection: $capeID) {
                                            Text("不显示披风").tag("")
                                            ForEach(appearance.capes) { cape in Text(cape.name).tag(cape.id) }
                                        }
                                    }
                                    AccountTexturePreview(texture: account.kind == .microsoft ? appearance.capes.first { $0.id == capeID } : appearance.activeCape, kind: .cape, client: client)
                                    if account.kind == .microsoft {
                                        if capeID != (appearance.activeCape?.id ?? "") {
                                            Button(capeID.isEmpty ? "隐藏披风" : "使用这件披风") {
                                                let selected = capeID
                                                change(selected.isEmpty ? "已隐藏披风" : "已更换披风") {
                                                    if selected.isEmpty { try await $0.reset(.cape, expecting: appearance) }
                                                    else { try await $0.selectCape(selected, expecting: appearance) }
                                                }
                                            }
                                        } else { Text(capeID.isEmpty ? "当前未使用披风" : "当前正在使用").font(.caption).foregroundStyle(.secondary) }
                                        if appearance.capes.isEmpty { Text("这个账号尚未拥有披风。").font(.caption).foregroundStyle(.secondary) }
                                    } else if appearance.uploadable.contains(.cape) {
                                        Button("选择披风 PNG…") { choose(.cape) }
                                        Button("移除当前披风") { change("已移除披风") { try await $0.reset(.cape, expecting: appearance) } }.disabled(appearance.activeCape == nil)
                                    } else { Text("此认证站未开放披风上传，请在认证站管理。").font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity).padding(10)
                            }
                        }.id(previewRevision).disabled(task != nil)
                        Text("更改会保存到此账号的认证服务。游戏中的外观可能需要重新进入服务器后才更新。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if task != nil { ProgressView("正在处理…").controlSize(.small) }
                Spacer()
                Button("刷新") { load() }.disabled(task != nil || draft != nil)
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).disabled(task != nil)
            }
        }.padding(26).frame(width: 680, height: 570).onAppear { load() }.onDisappear { task?.cancel() }
    }

    private func uploadEditor(_ image: PlayerTextureImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("准备上传\(draftKind.title)").font(.headline)
            TexturePixels(image: image).frame(maxWidth: .infinity)
            Text("\(image.width) × \(image.height) PNG").font(.caption).foregroundStyle(.secondary)
            if draftKind == .skin {
                Picker("皮肤模型", selection: $skinModel) { ForEach(PlayerSkinModel.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .disabled(image.isLegacySkin)
            }
            HStack {
                Button("重新选择…") { choose(draftKind) }
                Button("取消") { draft = nil; error = nil }
                Spacer()
                Button("上传到此账号") {
                    guard let appearance else { return }
                    let kind = draftKind, selectedModel = skinModel
                    change("已上传\(kind.title)") { try await $0.upload(image, kind: kind, model: selectedModel, expecting: appearance) }
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
                } catch { self.error = "更改已提交，但刷新外观失败：" + error.localizedDescription }
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
                .accessibilityLabel("展开的 PNG 纹理")
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
                Text("纹理预览").font(.caption2).foregroundStyle(.secondary)
                Button("保存 PNG…") { save(image) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            else if let error { Text(error).font(.caption).foregroundStyle(.secondary).frame(height: 180) }
            else if texture != nil { ProgressView().frame(height: 180) }
            else { Label(kind == .skin ? "使用默认皮肤" : "没有披风", systemImage: "person.crop.square").foregroundStyle(.secondary).frame(height: 180) }
        }.task(id: texture?.url) {
            image = nil; error = nil
            guard let texture else { return }
            do { let value = try await client.image(for: texture); try Task.checkCancellation(); image = value }
            catch { if !Task.isCancelled { self.error = "预览未能加载：" + error.localizedDescription } }
        }
    }
    private func save(_ image: PlayerTextureImage) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = kind.rawValue + ".png"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { try image.png.write(to: file, options: .atomic) } catch { self.error = error.localizedDescription }
    }
}
