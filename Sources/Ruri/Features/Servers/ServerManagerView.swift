import SwiftUI
import RuriCore
import RuriLocalization

/// One instance's multiplayer list, in the order the game shows it. Rows are
/// dragged to reorder; double-clicking one edits it and Delete removes it.
struct ServerManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var snapshot: ServerListSnapshot?
    @State private var failure: String?
    @State private var editor: ServerEditorRequest?
    @State private var removing: ServerEntry?
    @State private var selection: Int?
    @State private var refresh = UUID()
    @State private var reveal: ServerAddress?
    private var running: Bool { model.isInstanceInUse(instance.id) }
    private var readOnly: Bool { model.readOnly || model.busy || running }
    private var shared: Bool {
        let directory = model.paths.game(instance.id).standardizedFileURL.resolvingSymlinksInPath()
        return model.state.instances.filter { model.paths.game($0.id).standardizedFileURL.resolvingSymlinksInPath() == directory }.count > 1
    }

    var body: some View {
        InstanceManagementSheet(title: Messages.Servers.manage.localized, instanceName: instance.name) {
            HStack(spacing: 10) {
                if running {
                    Label(Messages.Servers.running.localized, systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.Servers.refresh.localized, systemImage: "arrow.clockwise") { refresh = UUID() }
                    .labelStyle(.iconOnly).help(Messages.Servers.refresh.localized)
                Button(Messages.Servers.add.localized, systemImage: "plus") { editor = .init(instanceID: instance.id) }
                    .disabled(readOnly)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                }
                if let snapshot {
                    if snapshot.entries.isEmpty {
                        ContentUnavailableView {
                            Label(Messages.Servers.emptyInstanceList.localized, systemImage: "server.rack")
                        } description: {
                            Text(Messages.Servers.emptyInstanceListDescription.localized)
                        } actions: {
                            Button(Messages.Servers.add.localized) { editor = .init(instanceID: instance.id) }.disabled(readOnly)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        list(snapshot)
                    }
                } else if failure == nil {
                    DelayedProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                if let snapshot, !snapshot.entries.isEmpty {
                    Text(Messages.Servers.serverCount(Int64(snapshot.entries.count)).localized)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if shared {
                    Text(Messages.Servers.sharedDirectory.localized).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if (snapshot?.entries.count ?? 0) > 1 && !readOnly {
                    Text(Messages.Servers.reorderHint.localized).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: $editor) { request in ServerEditorSheet(request: request) { _ in refresh = UUID() } }
        .confirmationDialog(Messages.Servers.deleteConfirm.localized, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(Messages.Servers.confirmRemove.localized, role: .destructive) { if let removing { apply(.remove(id: removing.id)) }; removing = nil }
        } message: { Text(removing.map { $0.name.isEmpty ? $0.address : $0.name } ?? "") }
        .task(id: refresh.uuidString + (model.state.revision?.uuidString ?? "")) {
            let paths = model.paths, id = instance.id
            let observer = FileChangeObserver(directories: [paths.game(id)], fallbackSeconds: 15)
            defer { observer.cancel() }
            await load(paths: paths, id: id)
            for await _ in observer.events { if Task.isCancelled { break }; await load(paths: paths, id: id) }
        }
        .onDisappear { if let reveal { model.showServer(reveal) } }
    }

    private func list(_ snapshot: ServerListSnapshot) -> some View {
        List(selection: $selection) {
            ForEach(snapshot.entries) { entry in
                row(entry, last: entry.id == snapshot.entries.count - 1).tag(entry.id)
            }
            .onMove { source, destination in
                guard source.count == 1, let from = source.first else { return }
                let target = destination > from ? destination - 1 : destination
                if target != from { apply(.move(id: from, to: target)) }
            }
            .moveDisabled(readOnly)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Int.self) { ids in
            if let entry = ids.first.flatMap({ id in snapshot.entries.first { $0.id == id } }) {
                actions(entry, last: entry.id == snapshot.entries.count - 1).labelStyle(.titleAndIcon)
            }
        } primaryAction: { ids in
            guard !readOnly, let entry = ids.first.flatMap({ id in snapshot.entries.first { $0.id == id } }) else { return }
            editor = .init(instanceID: instance.id, snapshot: snapshot, entry: entry)
        }
        .onDeleteCommand {
            if !readOnly, let selection, let entry = snapshot.entries.first(where: { $0.id == selection }) { removing = entry }
        }
    }

    private func row(_ entry: ServerEntry, last: Bool) -> some View {
        HStack(spacing: 12) {
            ServerIcon(data: entry.icon, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name.isEmpty ? entry.address : entry.name).font(.body.weight(.medium)).lineLimit(1)
                Text(entry.address).font(.caption).foregroundStyle(entry.endpoint == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if entry.resourcePacks != .ask {
                MetadataBadge(text: entry.resourcePacks.title, symbol: "shippingbox", compact: true)
                    .help(Messages.Servers.resourcePacks.localized)
            }
            Menu {
                actions(entry, last: last).labelStyle(.titleAndIcon)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(Messages.Servers.moreActions.localized).accessibilityLabel(Messages.Servers.moreActions.localized)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func actions(_ entry: ServerEntry, last: Bool) -> some View {
        Button(Messages.Servers.edit.localized, systemImage: "pencil") {
            editor = .init(instanceID: instance.id, snapshot: snapshot, entry: entry)
        }.disabled(readOnly)
        Button(Messages.Servers.moveUp.localized, systemImage: "arrow.up") { apply(.move(id: entry.id, to: entry.id - 1)) }
            .disabled(readOnly || entry.id == 0)
        Button(Messages.Servers.moveDown.localized, systemImage: "arrow.down") { apply(.move(id: entry.id, to: entry.id + 1)) }
            .disabled(readOnly || last)
        if let address = entry.endpoint {
            Divider()
            Button(Messages.Servers.copyAddress.localized, systemImage: "doc.on.doc") { copyServerAddress(address) }
            Button(Messages.Servers.showInServers.localized, systemImage: "server.rack") { reveal = address; dismiss() }
        }
        Divider()
        Button(Messages.Servers.remove.localized, systemImage: "trash", role: .destructive) { removing = entry }.disabled(readOnly)
    }

    private func load(paths: LauncherPaths, id: UUID) async {
        do {
            let result = try await Task.detached(priority: .utility) { try ServerListManager(paths: paths, instanceID: id).snapshot() }.value
            if !Task.isCancelled { snapshot = result; failure = nil }
        } catch { if !Task.isCancelled { snapshot = nil; failure = error.localizedDescription } }
    }

    private func apply(_ change: ServerListChange) {
        guard let snapshot, !readOnly else { return }
        do {
            self.snapshot = try ServerListManager(paths: model.paths, instanceID: instance.id).apply(change, to: snapshot); failure = nil
            if case .move(_, let target) = change { selection = target }
        } catch { failure = error.localizedDescription }
    }
}
