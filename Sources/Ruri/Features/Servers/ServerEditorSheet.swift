import SwiftUI
import RuriCore
import RuriLocalization

struct ServerEditorRequest: Identifiable {
    let id = UUID()
    var instanceID: UUID?
    var snapshot: ServerListSnapshot?
    var entry: ServerEntry?
    var item: ServerLibraryItem?
    /// The last known status, so the preview isn't blank while it's queried again.
    var status: ServerStatus?
}

/// Adds a server, edits an entry in an instance's multiplayer list, or edits
/// the launcher's own settings for a server. A preview at the top shows what
/// the address answers as it is typed.
struct ServerEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ServerEditorRequest
    var completed: (ServerAddress) -> Void
    @State private var address: String
    @State private var name: String
    @State private var notes: String
    @State private var selectedInstance: UUID?
    @State private var favorite: Bool
    @State private var packs: ServerResourcePacks
    @State private var error: String?
    @State private var status: ServerStatus?
    @State private var queryError: String?
    @State private var querying = false
    @State private var saving = false
    @State private var savedEntry = false
    @State private var queryRequest = UUID()
    private var preferences: Bool { request.item != nil }
    private var isNew: Bool { request.item == nil && request.entry == nil }
    private var endpoint: ServerAddress? { try? ServerAddress(address) }
    private var instanceBusy: Bool { !preferences && selectedInstance.map { model.isInstanceInUse($0) } == true }
    private var title: String { preferences ? Messages.Servers.globalSettings.localized : isNew ? Messages.Servers.add.localized : Messages.Servers.edit.localized }
    private var subtitle: String? {
        if let item = request.item { return item.address.authority }
        if let id = request.instanceID, !isNew { return model.state.instances.first { $0.id == id }?.name }
        return nil
    }

    init(request: ServerEditorRequest, completed: @escaping (ServerAddress) -> Void) {
        self.request = request; self.completed = completed
        _address = State(initialValue: request.entry?.address ?? request.item?.address.authority ?? "")
        _name = State(initialValue: request.entry?.name ?? request.item?.preference?.alias ?? "")
        _notes = State(initialValue: request.item?.preference?.notes ?? "")
        _selectedInstance = State(initialValue: request.instanceID ?? request.item?.preference?.preferredInstanceID)
        _favorite = State(initialValue: request.item?.preference?.favorite ?? false)
        _packs = State(initialValue: request.entry?.resourcePacks ?? .ask)
        _status = State(initialValue: request.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.semibold))
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 4)
            Form {
                Section { preview }
                Section {
                    if preferences {
                        LabeledContent(Messages.Servers.address.localized) {
                            Text(address).font(.body.monospaced()).textSelection(.enabled)
                        }
                        TextField(Messages.Servers.displayName.localized, text: $name, prompt: Text(request.item?.name ?? ""))
                    } else {
                        TextField(Messages.Servers.address.localized, text: $address, prompt: Text(Messages.Servers.addressPlaceholder.localized))
                        TextField(Messages.Servers.name.localized, text: $name, prompt: Text(endpoint?.authority ?? ""))
                    }
                }
                if preferences {
                    Section {
                        Toggle(Messages.Servers.favorite.localized, isOn: $favorite)
                        Picker(Messages.Servers.preferredInstance.localized, selection: $selectedInstance) {
                            Text(Messages.Servers.automaticInstance.localized).tag(nil as UUID?)
                            ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                        }
                    } footer: { footnote(Messages.Servers.settingsFooter.localized) }
                    Section(Messages.Servers.notes.localized) {
                        TextField(Messages.Servers.notes.localized, text: $notes, axis: .vertical).lineLimit(4...8).labelsHidden()
                    }
                } else {
                    if isNew {
                        Section {
                            Picker(Messages.Servers.saveTo.localized, selection: $selectedInstance) {
                                Text(Messages.Servers.independent.localized).tag(nil as UUID?)
                                if !model.state.instances.isEmpty {
                                    Divider()
                                    ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                                }
                            }.disabled(request.instanceID != nil)
                            Toggle(Messages.Servers.favorite.localized, isOn: $favorite)
                        } footer: {
                            footnote(selectedInstance == nil ? Messages.Servers.favoriteOnlyFooter.localized : Messages.Servers.saveToFooter.localized)
                        }
                    }
                    if selectedInstance != nil {
                        Section {
                            Picker(Messages.Servers.resourcePacks.localized, selection: $packs) {
                                ForEach(ServerResourcePacks.allCases, id: \.self) { policy in Text(policy.title).tag(policy) }
                            }
                        } footer: {
                            if instanceBusy { footnote(Messages.Servers.running.localized, symbol: "lock.fill") }
                        }
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(Messages.Servers.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.Servers.save.localized) { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(saving || model.readOnly || endpoint == nil || instanceBusy)
            }
            .padding(20)
        }
        .frame(width: 540, height: preferences ? 600 : 560)
        .onChange(of: address) { status = nil; queryError = nil }
        .task(id: address + queryRequest.uuidString) {
            querying = false
            guard let endpoint else { status = nil; queryError = nil; return }
            // Wait for typing to pause, except for the first look at a known server.
            if !(preferences && status == nil) { do { try await Task.sleep(for: .milliseconds(500)) } catch { return } }
            querying = true
            defer { if !Task.isCancelled { querying = false } }
            do {
                let result = try await ServerStatusClient.query(endpoint)
                if !Task.isCancelled { status = result; queryError = nil }
            } catch {
                if !Task.isCancelled { status = nil; queryError = error.localizedDescription }
            }
        }
    }

    // MARK: Preview

    private var previewName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return request.item?.name ?? endpoint?.authority ?? Messages.Servers.add.localized
    }

    /// How the server will look in the list, and whether it answers.
    private var preview: some View {
        HStack(spacing: 14) {
            ServerIcon(data: status?.icon ?? request.entry?.icon ?? request.item?.icon, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(previewName).font(.headline).lineLimit(1)
                Group {
                    if endpoint == nil {
                        Text(address.isEmpty ? Messages.Servers.previewPrompt.localized : Messages.Servers.invalidAddress.localized)
                            .foregroundStyle(address.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    } else if let status {
                        let motd = status.description.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
                        if let motd { Text(motd).foregroundStyle(.secondary).lineLimit(1) }
                        HStack(spacing: 8) {
                            ServerSignal(reachability: .online(status))
                            Text([status.playersLabel, status.latencyMilliseconds.map { Messages.Servers.milliseconds(Int64($0)).localized }, status.version]
                                .compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                        }.foregroundStyle(.secondary)
                    } else if querying {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(Messages.Servers.querying.localized) }.foregroundStyle(.secondary)
                    } else if let queryError {
                        HStack(spacing: 6) {
                            Image(systemName: "network.slash").foregroundStyle(.red)
                            Text(queryError).foregroundStyle(.secondary)
                        }
                        .help(Messages.Servers.queryHint.localized)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
            Button { queryRequest = UUID() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(endpoint == nil || querying)
                .help(Messages.Servers.refreshStatus.localized).accessibilityLabel(Messages.Servers.refreshStatus.localized)
        }
        .padding(.vertical, 4)
    }

    private func footnote(_ text: String, symbol: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Saving

    private func save() {
        saving = true
        defer { saving = false }
        error = nil
        do {
            let endpoint = try ServerAddress(address)
            if preferences {
                let alias = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = ServerPreference(address: endpoint, favorite: favorite, saved: request.item?.preference?.saved ?? false, alias: alias, notes: notes, preferredInstanceID: selectedInstance)
                model.acceptState(try ServerLibrary.save(value, paths: model.basePaths))
            } else {
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? endpoint.authority : name
                if let id = selectedInstance, !savedEntry {
                    let manager = ServerListManager(paths: model.paths, instanceID: id)
                    let snapshot = try request.snapshot ?? manager.snapshot()
                    let change: ServerListChange = request.entry.map { .edit(id: $0.id, name: title, address: endpoint, resourcePacks: packs) } ?? .add(name: title, address: endpoint, resourcePacks: packs)
                    try manager.apply(change, to: snapshot)
                    savedEntry = true
                }
                // A server kept only in Ruri is saved in its library, pinned or not.
                if isNew && (favorite || selectedInstance == nil) {
                    var value = model.state.servers?.first { $0.id == endpoint.key } ?? .init(address: endpoint)
                    if favorite { value.favorite = true }
                    if selectedInstance == nil { value.saved = true }
                    if value.alias.isEmpty { value.alias = title == endpoint.authority ? "" : title }
                    model.acceptState(try ServerLibrary.save(value, paths: model.basePaths))
                }
            }
            completed(endpoint); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
