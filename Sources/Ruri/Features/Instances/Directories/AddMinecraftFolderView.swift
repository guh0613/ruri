import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

struct AddMinecraftFolderView: View {
    @Environment(AppModel.self) private var model
    let cancel: () -> Void
    let completed: @MainActor @Sendable (UUID) -> Void
    @State private var location: URL?
    @State private var scanID = UUID()
    @State private var previews: [MinecraftFolderPreview] = []
    @State private var selected: URL?
    @State private var name = ""
    @State private var draftNames: [String: String] = [:]
    @State private var checking = false
    @State private var checkingSuggestion: URL?
    @State private var issue: String?
    @FocusState private var nameFocused: Bool

    private var preview: MinecraftFolderPreview? { previews.first { $0.id == selected } }
    private var loadingManualSelection: Bool { checking && checkingSuggestion == nil && location != nil }
    private var existing: GameDirectory? { model.state.gameDirectories?.first { $0.url.standardizedFileURL.resolvingSymlinksInPath().path == selected?.path } }
    private var removed: DetachedMinecraftFolder? { model.state.detachedMinecraftFolders?.first { $0.directory.url.standardizedFileURL.resolvingSymlinksInPath().path == selected?.path } }
    private var suggestions: [MinecraftFolderSuggestion] {
        MinecraftFolderDiscovery.suggestions(locations: model.detectedMinecraftLocations ?? [], directories: model.state.gameDirectories ?? [],
                                             removedDirectories: (model.state.detachedMinecraftFolders ?? []).map(\.directory))
    }
    private var confirmationTitle: String {
        if existing != nil { return Messages.FolderExperience.openExisting.localized }
        if removed != nil { return Messages.AppGameDirectoriesView.readdFolder.localized }
        return Messages.FolderExperience.add.localized
    }
    private var validName: Bool { (try? GameDirectory.validName(name)) != nil }
    private var duplicateName: Bool {
        ([Messages.AppGameDirectoriesView.defaultInstanceFolder.localized] + (model.state.gameDirectories ?? []).map(\.name))
            .contains { $0.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "folder.badge.plus").font(.system(size: 32)).foregroundStyle(.tint).symbolRenderingMode(.hierarchical)
                Text(Messages.FolderExperience.addTitle.localized).font(.title2.weight(.semibold))
                Spacer()
            }.padding(24)
            Divider()
            Group {
                if preview != nil { previewContent }
                else if loadingManualSelection { pendingSelectionContent }
                else { selectionContent }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(model.busy || model.readOnly)
            Divider()
            HStack(spacing: 12) {
                if model.busy { ProgressView(Messages.FolderExperience.adding.localized).controlSize(.small) }
                else if location != nil {
                    Button(Messages.FolderExperience.back.localized, systemImage: "chevron.left", action: goBack)
                        .keyboardShortcut("[", modifiers: .command)
                }
                Spacer(minLength: 8)
                Button(Messages.Common.cancel.localized, action: cancel).keyboardShortcut(.cancelAction).disabled(model.busy)
                if preview == nil && !loadingManualSelection {
                    Button(Messages.FolderExperience.chooseLocation.localized, action: choose)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(model.busy || model.readOnly)
                } else {
                    Button(confirmationTitle, action: add)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(preview == nil || (existing == nil && !validName) || checking || model.busy || model.readOnly)
                }
            }.padding(20)
        }.frame(width: 620, height: 560)
        .interactiveDismissDisabled(model.busy)
        .task { await model.refreshMinecraftFolderSuggestions() }
        .task(id: scanID) {
            guard let location else { return }
            let requestID = scanID
            let names = [Messages.AppGameDirectoriesView.defaultInstanceFolder.localized] + (model.state.gameDirectories ?? []).map(\.name)
            let registration = suggestions.first { $0.directory.path == location.standardizedFileURL.path }?.registration
            let task = Task.detached(priority: .userInitiated) {
                try registration?.validateAvailability()
                return try MinecraftFolderDiscovery.inspect(location, existingNames: names)
            }
            do {
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                guard scanID == requestID else { return }
                previews = result
                if result.count == 1 { selected = result[0].id }
            } catch { if !Task.isCancelled, scanID == requestID { issue = error.localizedDescription } }
            if !Task.isCancelled, scanID == requestID { checking = false; checkingSuggestion = nil }
        }
        .onChange(of: selected) { previous, current in
            if let previous { draftNames[previous.path] = name }
            name = current.flatMap { draftNames[$0.path] } ?? existing?.name ?? removed?.directory.name ?? preview?.suggestedName ?? ""
            nameFocused = preview != nil && existing == nil
        }
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Messages.FolderExperience.locationHelp.localized).fixedSize(horizontal: false, vertical: true)
                Text(Messages.FolderExperience.newFolderHelp.localized).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
            Form {
                if let issue = issue ?? model.minecraftFolderDiscoveryError {
                    Section { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                }
                if previews.count > 1 {
                    Section(Messages.FolderExperience.chooseResult.localized) {
                        ForEach(previews) { item in
                            candidateRow(item.directory, title: item.suggestedName,
                                         detail: Messages.FolderExperience.versionsFound(Int64(item.versionNames.count)).localized) { selected = item.id }
                        }
                    }
                } else {
                    Section {
                        if !model.discoveringMinecraftLocations, suggestions.isEmpty {
                            Text(Messages.FolderExperience.noSuggestions.localized).foregroundStyle(.secondary).padding(.vertical, 12)
                        } else {
                            ForEach(suggestions) { item in
                                candidateRow(item.directory, title: item.name, status: statusTitle(item.status),
                                             isLoading: checking && checkingSuggestion?.path == item.directory.path) {
                                    beginScan(item.directory, fromSuggestion: true)
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text(Messages.FolderExperience.commonLocations.localized)
                            Spacer()
                            Group {
                                if model.discoveringMinecraftLocations { ProgressView().controlSize(.mini) }
                                else {
                                    Button(Messages.FolderExperience.refreshDiscovery.localized, systemImage: "arrow.clockwise") {
                                        Task { await model.refreshMinecraftFolderSuggestions(force: true) }
                                    }.labelStyle(.iconOnly).buttonStyle(.plain).help(Messages.FolderExperience.refreshDiscovery.localized)
                                }
                            }.frame(width: 20, height: 20)
                        }
                    }
                }
            }.formStyle(.grouped)
        }
    }

    private func statusTitle(_ status: MinecraftFolderSuggestion.Status) -> String? {
        switch status {
        case .detected: nil
        case .added: Messages.FolderExperience.activeFolders.localized
        case .removed: Messages.FolderExperience.removedFolder.localized
        }
    }

    private func candidateRow(_ url: URL, title: String, detail: String? = nil, status: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title3).foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).fontWeight(.medium)
                    Text((url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                Group {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.mini)
                            .accessibilityLabel(Messages.FolderExperience.checking.localized)
                    } else {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }.frame(width: 16, height: 16)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).help(url.path).disabled(isLoading)
    }

    private var previewContent: some View {
        Form {
            if previews.count > 1 {
                Section {
                    Picker(Messages.FolderExperience.chooseResult.localized, selection: $selected) {
                        if selected == nil { Text(Messages.FolderExperience.chooseResult.localized).tag(URL?.none) }
                        ForEach(previews) { item in Text(item.directory.path).tag(Optional(item.id)) }
                    }
                } footer: { Text(Messages.FolderExperience.multipleResults.localized) }
            }
            if let preview {
                Section {
                    folderLocationRow(preview.directory)
                } header: { Text(Messages.FolderExperience.folderLocation.localized) }
                if let existing {
                    Section { Label(Messages.FolderExperience.alreadyAdded(existing.name).localized, systemImage: "checkmark.circle") }
                } else {
                    Section {
                        HStack(spacing: 16) {
                            Text(Messages.FolderExperience.libraryName.localized)
                            TextField(Messages.FolderExperience.libraryName.localized, text: $name, prompt: Text(Messages.FolderExperience.namePlaceholder.localized))
                                .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                                .focused($nameFocused).accessibilityLabel(Messages.FolderExperience.libraryName.localized)
                        }
                        if !name.isEmpty, !validName { Text(Messages.FolderExperience.invalidName.localized).font(.caption).foregroundStyle(.orange) }
                        else if duplicateName { Text(Messages.FolderExperience.duplicateName.localized).font(.caption).foregroundStyle(.secondary) }
                        if let removed {
                            Label(Messages.AppGameDirectoriesView.preserveDetachedSettings(Int64(removed.instances.count)).localized, systemImage: "arrow.counterclockwise")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } footer: { Text(Messages.FolderExperience.nameHelp.localized) }
                }
                if preview.versions.isEmpty {
                    Section {
                        Label(Messages.FolderExperience.emptyFolder.localized, systemImage: "tray").foregroundStyle(.secondary)
                    } footer: { Text(Messages.FolderExperience.emptyFolderHelp.localized) }
                } else {
                    Section {
                        ForEach(preview.versions) { version in versionRow(version) }
                    } header: {
                        Text(Messages.FolderExperience.versionsFound(Int64(preview.versions.count)).localized)
                    } footer: {
                        if preview.issueCount > 0 {
                            Text(Messages.FolderExperience.versionsNeedAttention(Int64(preview.issueCount)).localized).foregroundStyle(.orange)
                        }
                    }
                }
            }
            if let issue { Section { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) } }
        }.formStyle(.grouped)
    }

    private var pendingSelectionContent: some View {
        Form {
            if let location {
                Section(Messages.FolderExperience.folderLocation.localized) {
                    folderLocationRow(location, isLoading: true)
                }
            }
        }.formStyle(.grouped)
    }

    private func folderLocationRow(_ url: URL, isLoading: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(url.lastPathComponent).fontWeight(.medium)
                Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !isLoading, url.path != location?.standardizedFileURL.resolvingSymlinksInPath().path {
                    Label(Messages.FolderExperience.detectedInside.localized, systemImage: "sparkle.magnifyingglass")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isLoading {
                ProgressView().controlSize(.small).accessibilityLabel(Messages.FolderExperience.checking.localized)
            } else {
                Button(Messages.FolderExperience.changeLocation.localized, action: choose)
            }
        }.padding(.vertical, 4)
    }

    private func versionRow(_ version: MinecraftFolderVersionPreview) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: version.issue == nil ? "gamecontroller" : "exclamationmark.triangle")
                .font(.title3).foregroundStyle(version.issue == nil ? Color.secondary : .orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(version.id).fontWeight(.medium).textSelection(.enabled)
                Text(version.issue ?? version.subtitle).font(.caption)
                    .foregroundStyle(version.issue == nil ? Color.secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }

    private func goBack() {
        nameFocused = false; issue = nil
        if selected != nil, previews.count > 1 {
            selected = nil
        } else {
            location = nil; selected = nil; previews = []; checking = false
            checkingSuggestion = nil
            scanID = UUID()
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false
        panel.message = Messages.FolderExperience.locationHelp.localized
        panel.prompt = Messages.FolderExperience.chooseLocation.localized
        panel.directoryURL = location
        guard panel.runModal() == .OK, let url = panel.url else { return }
        beginScan(url)
    }

    private func beginScan(_ url: URL, fromSuggestion: Bool = false) {
        location = url; checkingSuggestion = fromSuggestion ? url : nil
        previews = []; selected = nil; issue = nil; checking = true
        scanID = UUID()
    }

    private func add() {
        guard let preview else { return }
        issue = nil
        model.addMinecraftDirectory(name: existing?.name ?? name, at: preview.directory, expectedDirectory: existing ?? removed?.directory,
                                    failed: { issue = $0 }, completed: completed)
    }
}
