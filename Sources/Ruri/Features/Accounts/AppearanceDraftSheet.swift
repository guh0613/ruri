import RuriLocalization
import SwiftUI
import RuriCore

/// A skin or cape the player has picked but not yet applied.
struct AppearanceDraft: Identifiable {
    let id = UUID()
    let image: PlayerTextureImage
    let kind: PlayerTextureKind
    var name: String
    var model: PlayerSkinModel
}

/// Confirms a picked texture before it touches the account: the character is
/// shown wearing it, the arm model and library name can be adjusted, and the
/// sheet only closes once the change has been applied.
struct AppearanceDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let account: Account
    let currentSkin: PlayerTextureImage?
    let currentSkinModel: PlayerSkinModel
    let currentCape: PlayerTextureImage?
    let canApply: Bool
    let chooseAgain: () -> Void
    let saveToLibrary: (AppearanceDraft) throws -> Void
    let apply: (AppearanceDraft) async throws -> Void
    @State private var draft: AppearanceDraft
    @State private var error: String?
    @State private var saved = false
    @State private var task: Task<Void, Never>?
    private var previewSkin: PlayerTextureImage? { draft.kind == .skin ? draft.image : currentSkin }
    private var previewModel: PlayerSkinModel { draft.kind == .skin ? draft.model : currentSkinModel }
    private var previewCape: PlayerTextureImage? { draft.kind == .cape ? draft.image : currentCape }
    private var applyTitle: String {
        if account.kind != .offline { return Messages.AppAccountAppearanceView.uploadToAccount.localized }
        return draft.kind == .skin ? Messages.AccountCenter.useLocalPreview.localized : Messages.AccountCenter.applyCape.localized
    }

    init(draft: AppearanceDraft, account: Account, currentSkin: PlayerTextureImage?, currentSkinModel: PlayerSkinModel, currentCape: PlayerTextureImage?,
         canApply: Bool, chooseAgain: @escaping () -> Void, saveToLibrary: @escaping (AppearanceDraft) throws -> Void, apply: @escaping (AppearanceDraft) async throws -> Void) {
        _draft = State(initialValue: draft)
        self.account = account; self.currentSkin = currentSkin; self.currentSkinModel = currentSkinModel; self.currentCape = currentCape
        self.canApply = canApply; self.chooseAgain = chooseAgain; self.saveToLibrary = saveToLibrary; self.apply = apply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Messages.AccountCenter.previewBeforeApply.localized).font(.title2.weight(.semibold))
                Text(Messages.AccountCenter.confirmAppearanceHelp.localized).font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            HStack(alignment: .top, spacing: 24) {
                PlayerSkinPreview(image: previewSkin, model: previewModel, cape: previewCape, height: 272)
                    .frame(width: 236)
                VStack(alignment: .leading, spacing: 18) {
                    if draft.kind == .skin {
                        field(Messages.AccountCenter.skinName.localized) {
                            TextField(Messages.AccountCenter.skinName.localized, text: $draft.name).textFieldStyle(.roundedBorder).labelsHidden()
                        }
                        field(Messages.AppAccountAppearanceView.skinModel.localized) {
                            Picker(Messages.AppAccountAppearanceView.skinModel.localized, selection: $draft.model) {
                                ForEach(PlayerSkinModel.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().disabled(draft.image.isLegacySkin)
                            if draft.image.isLegacySkin {
                                Text(Messages.AccountCenter.legacySkinHelp.localized).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    field(draft.kind.title) {
                        Text(Messages.AccountCenter.textureSize(Int64(draft.image.width), Int64(draft.image.height)).localized)
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if draft.kind == .skin {
                        HStack(spacing: 10) {
                            Button(Messages.AccountCenter.saveToLibrary.localized) {
                                error = nil
                                do { try saveToLibrary(draft); withAnimation(.snappy) { saved = true } } catch { self.error = error.localizedDescription }
                            }.disabled(saved || model.readOnly)
                            if saved {
                                Label(Messages.AccountCenter.savedToLibrary.localized, systemImage: "checkmark.circle.fill")
                                    .font(.callout).foregroundStyle(.secondary).transition(.opacity)
                            }
                        }
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }.padding(24).disabled(task != nil)
            Divider()
            HStack(spacing: 12) {
                Button(Messages.AppAccountAppearanceView.chooseAgain.localized, action: chooseAgain).disabled(task != nil)
                if task != nil {
                    ProgressView().controlSize(.small)
                    Text(Messages.AccountCenter.applyingAppearance.localized).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.Common.cancel.localized) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(applyTitle) { run() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(task != nil || !canApply || model.readOnly || (draft.kind == .skin && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }.padding(20)
        }
        .frame(width: 640)
        .onChange(of: draft.model) { saved = false }
        .onChange(of: draft.name) { saved = false }
        .onDisappear { task?.cancel() }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }
    private func run() {
        guard task == nil else { return }
        error = nil
        task = Task {
            defer { task = nil }
            do { try await apply(draft); dismiss() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
