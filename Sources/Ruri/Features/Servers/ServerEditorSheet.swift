import SwiftUI
import RuriCore
import RuriLocalization

struct ServerEditorRequest: Identifiable {
    let id = UUID()
    var instanceID: UUID?
    var snapshot: ServerListSnapshot?
    var entry: ServerEntry?
    var item: ServerLibraryItem?
}

struct ServerEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ServerEditorRequest
    var completed: () -> Void
    @State private var address: String
    @State private var name: String
    @State private var notes: String
    @State private var selectedInstance: UUID?
    @State private var favorite: Bool
    @State private var packs: ServerResourcePacks
    @State private var error: String?
    @State private var status: ServerStatus?
    @State private var querying = false
    @State private var saving = false
    @State private var savedEntry = false
    @State private var queryRequest = UUID()
    private var preferences: Bool { request.item != nil }
    private var isNew: Bool { request.item == nil && request.entry == nil }
    init(request: ServerEditorRequest, completed: @escaping () -> Void) {
        self.request = request; self.completed = completed
        _address = State(initialValue: request.entry?.address ?? request.item?.address.authority ?? "")
        _name = State(initialValue: request.entry?.name ?? request.item?.preference?.alias ?? "")
        _notes = State(initialValue: request.item?.preference?.notes ?? "")
        _selectedInstance = State(initialValue: request.instanceID ?? request.item?.preference?.preferredInstanceID)
        _favorite = State(initialValue: request.item?.preference?.favorite ?? (request.instanceID == nil))
        _packs = State(initialValue: request.entry?.resourcePacks ?? .ask)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(preferences ? Messages.Servers.globalSettings.localized : isNew ? Messages.Servers.add.localized : Messages.Servers.edit.localized).font(.title2.weight(.semibold))
            Form {
                TextField(Messages.Servers.address.localized, text: $address).disabled(preferences)
                TextField(preferences ? Messages.Servers.alias.localized : Messages.Servers.name.localized, text: $name)
                if preferences {
                    TextField(Messages.Servers.notes.localized, text: $notes, axis: .vertical).lineLimit(3...6)
                    Toggle(Messages.Servers.favorite.localized, isOn: $favorite)
                    Picker(Messages.Servers.preferredInstance.localized, selection: $selectedInstance) {
                        Text(Messages.Servers.chooseInstance.localized).tag(nil as UUID?)
                        ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                    }
                } else {
                    if isNew {
                        Picker(Messages.Servers.instanceName.localized, selection: $selectedInstance) {
                            Text(Messages.Servers.independent.localized).tag(nil as UUID?)
                            ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                        }.disabled(request.instanceID != nil)
                        Toggle(Messages.Servers.favorite.localized, isOn: $favorite)
                    }
                    if selectedInstance != nil {
                        Picker(Messages.Servers.resourcePacks.localized, selection: $packs) {
                            ForEach(ServerResourcePacks.allCases, id: \.self) { policy in Text(policy.title).tag(policy) }
                        }
                    }
                }
            }.formStyle(.grouped)
            if !preferences {
                HStack {
                    Button(Messages.Servers.probe.localized) { queryRequest = UUID() }.disabled((try? ServerAddress(address)) == nil || querying)
                    if querying { ProgressView().controlSize(.small) }
                    if let status { Text(status.description).font(.callout).lineLimit(2).foregroundStyle(.secondary) }
                }
                Text(Messages.Servers.queryHint.localized).font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button(Messages.Servers.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.Servers.save.localized) { save() }.keyboardShortcut(.defaultAction)
                    .disabled(saving || model.readOnly || (isNew && selectedInstance == nil && !favorite) || selectedInstance.map { model.isInstanceInUse($0) && !preferences } == true)
            }
        }.padding(24).frame(width: 520)
        .task(id: address + queryRequest.uuidString) {
            guard !preferences, let endpoint = try? ServerAddress(address) else { status = nil; return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            querying = true
            do { let result = try await ServerStatusClient.query(endpoint); if !Task.isCancelled { status = result; error = nil } }
            catch { if !Task.isCancelled { status = nil; self.error = error.localizedDescription } }
            querying = false
        }
    }
    private func save() {
        saving = true
        defer { saving = false }
        do {
            let endpoint = try ServerAddress(address)
            if preferences {
                let value = ServerPreference(address: endpoint, favorite: favorite, alias: name, notes: notes, preferredInstanceID: selectedInstance)
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
                if isNew && favorite {
                    var value = model.state.servers?.first { $0.id == endpoint.key } ?? .init(address: endpoint)
                    value.favorite = true; value.alias = title
                    model.acceptState(try ServerLibrary.save(value, paths: model.basePaths))
                }
            }
            completed(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ServerManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var snapshot: ServerListSnapshot?
    @State private var failure: String?
    @State private var editor: ServerEditorRequest?
    @State private var removing: ServerEntry?
    @State private var refresh = UUID()
    private var readOnly: Bool { model.readOnly || model.busy || model.isInstanceInUse(instance.id) }
    var body: some View {
        InstanceManagementSheet(title: Messages.Servers.manage.localized, instanceName: instance.name) {
            HStack {
                Button(Messages.Servers.add.localized, systemImage: "plus") { editor = .init(instanceID: instance.id) }.disabled(readOnly)
                Button(Messages.Servers.refresh.localized, systemImage: "arrow.clockwise") { refresh = UUID() }
                Spacer()
                if model.isInstanceInUse(instance.id) { Label(Messages.Servers.running.localized, systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if let failure { Text(failure).foregroundStyle(.red).padding() }
                if let snapshot {
                    List {
                        ForEach(snapshot.entries) { entry in
                            HStack(spacing: 12) {
                                ServerIcon(data: entry.icon, size: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline)
                                    Text(entry.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                Text(entry.resourcePacks.title).font(.caption).foregroundStyle(.secondary)
                                Button { apply(.move(id: entry.id, to: entry.id - 1)) } label: { Image(systemName: "arrow.up") }.help(Messages.Servers.moveUp.localized).disabled(readOnly || entry.id == 0)
                                Button { apply(.move(id: entry.id, to: entry.id + 1)) } label: { Image(systemName: "arrow.down") }.help(Messages.Servers.moveDown.localized).disabled(readOnly || entry.id == snapshot.entries.count - 1)
                                Button { editor = .init(instanceID: instance.id, snapshot: snapshot, entry: entry) } label: { Image(systemName: "pencil") }.help(Messages.Servers.edit.localized).disabled(readOnly)
                                Button(role: .destructive) { removing = entry } label: { Image(systemName: "trash") }.help(Messages.Servers.remove.localized).disabled(readOnly)
                            }.padding(.vertical, 5)
                        }
                    }
                    .overlay { if snapshot.entries.isEmpty { ContentUnavailableView(Messages.Servers.empty.localized, systemImage: "server.rack") } }
                } else if failure == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        } footer: {
            HStack {
                if model.state.instances.filter({ model.paths.game($0.id).standardizedFileURL.resolvingSymlinksInPath() == model.paths.game(instance.id).standardizedFileURL.resolvingSymlinksInPath() }).count > 1 {
                    Text(Messages.Servers.sharedDirectory.localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Button(Messages.Servers.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .sheet(item: $editor) { request in ServerEditorSheet(request: request) { refresh = UUID() } }
        .confirmationDialog(Messages.Servers.deleteConfirm.localized, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(Messages.Servers.confirmRemove.localized, role: .destructive) { if let removing { apply(.remove(id: removing.id)) }; removing = nil }
        }
        .task(id: refresh.uuidString + (model.state.revision?.uuidString ?? "")) {
            let paths = model.paths, id = instance.id
            let observer = FileChangeObserver(directories: [paths.game(id)], fallbackSeconds: 15)
            defer { observer.cancel() }
            await load(paths: paths, id: id)
            for await _ in observer.events { if Task.isCancelled { break }; await load(paths: paths, id: id) }
        }
    }
    private func load(paths: LauncherPaths, id: UUID) async {
        do {
            let result = try await Task.detached(priority: .utility) { try ServerListManager(paths: paths, instanceID: id).snapshot() }.value
            if !Task.isCancelled { snapshot = result; failure = nil }
        } catch { if !Task.isCancelled { snapshot = nil; failure = error.localizedDescription } }
    }
    private func apply(_ change: ServerListChange) {
        guard let snapshot, !readOnly else { return }
        do { self.snapshot = try ServerListManager(paths: model.paths, instanceID: instance.id).apply(change, to: snapshot); failure = nil }
        catch { failure = error.localizedDescription }
    }
}
