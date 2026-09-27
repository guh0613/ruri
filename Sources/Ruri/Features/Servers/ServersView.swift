import SwiftUI
import AppKit
import Observation
import RuriCore
import RuriLocalization

@MainActor @Observable final class ServerNavigationState {
    var search = ""
    var scope = "all"
    var instanceID: UUID?
    var selectedID: String?
    var snapshot: ServerLibrarySnapshot?
    var responses: [String: ServerStatus] = [:]
    var failures: [String: String] = [:]
    var querying = Set<String>()
    var refreshID = UUID()
    var queryID = UUID()
    var editor: ServerEditorRequest?
    var joining = false

    func load(paths: LauncherPaths, state: PersistentState) async {
        let result = await Task.detached(priority: .utility) { ServerLibrary.load(paths: paths, state: state) }.value
        guard !Task.isCancelled else { return }
        snapshot = result
    }
    func refresh(_ addresses: [ServerAddress]) async {
        let generation = UUID(); queryID = generation
        querying = Set(addresses.map(\.key))
        defer { if queryID == generation { querying = [] } }
        await withTaskGroup(of: (String, ServerStatus?, String?).self) { group in
            var pending = addresses.makeIterator()
            func enqueue(_ address: ServerAddress) {
                group.addTask {
                    do { return (address.key, try await ServerStatusClient.query(address), nil) }
                    catch { return (address.key, nil, error.localizedDescription) }
                }
            }
            for _ in 0..<4 { if let address = pending.next() { enqueue(address) } }
            while let (key, response, error) = await group.next() {
                guard !Task.isCancelled, queryID == generation else { group.cancelAll(); return }
                querying.remove(key)
                if let response {
                    responses[key] = response; failures[key] = nil
                    if responses.count > 256, let oldest = responses.min(by: { $0.value.queriedAt < $1.value.queriedAt })?.key { responses[oldest] = nil }
                }
                else { failures[key] = error }
                if let address = pending.next() { enqueue(address) }
            }
        }
    }
    func label(for key: String) -> String {
        if querying.contains(key) { return Messages.Servers.querying.localized }
        if let error = failures[key] { return error }
        return responses[key] == nil ? Messages.Servers.unknown.localized : Messages.Servers.reachable.localized
    }
}

struct ServersView: View {
    @Environment(AppModel.self) private var model
    let column: NavigationSplitViewColumn
    @Bindable var navigation: ServerNavigationState
    private var filtered: [ServerLibraryItem] {
        (navigation.snapshot?.items ?? []).filter { item in
            (navigation.scope != "favorites" || item.preference?.favorite == true) &&
            (navigation.scope != "recent" || navigation.snapshot?.history[item.id] != nil) &&
            (navigation.instanceID == nil || (item.instanceIDs + item.playedInstanceIDs).contains(navigation.instanceID!)) &&
            (navigation.search.isEmpty || item.name.localizedCaseInsensitiveContains(navigation.search) || item.address.authority.localizedCaseInsensitiveContains(navigation.search))
        }.sorted { first, second in
            if navigation.scope == "recent" { return (navigation.snapshot?.history[first.id]?.lastPlayed ?? .distantPast) > (navigation.snapshot?.history[second.id]?.lastPlayed ?? .distantPast) }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
    private var current: ServerLibraryItem? { filtered.first { $0.id == navigation.selectedID } ?? filtered.first }
    var body: some View {
        if column == .content { content }
        else {
            Group {
                if let item = current { ServerDetailView(item: item, navigation: navigation).id(item.id) }
                else { ContentUnavailableView(Messages.Servers.noSelection.localized, systemImage: "server.rack") }
            }
            .sheet(item: $navigation.editor) { request in ServerEditorSheet(request: request) { navigation.refreshID = UUID() } }
            .toolbar { RootToolbar(model: model) }
        }
    }
    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField(Messages.Servers.search.localized, text: $navigation.search).textFieldStyle(.roundedBorder)
                Picker(Messages.Servers.page.localized, selection: $navigation.scope) {
                    Text(Messages.Servers.all.localized).tag("all")
                    Text(Messages.Servers.favorites.localized).tag("favorites")
                    Text(Messages.Servers.recent.localized).tag("recent")
                }.pickerStyle(.segmented).labelsHidden()
                Picker(Messages.Servers.instanceName.localized, selection: $navigation.instanceID) {
                    Text(Messages.Servers.all.localized).tag(nil as UUID?)
                    ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                }
            }.padding(12)
            if let snapshot = navigation.snapshot, !snapshot.errors.isEmpty {
                Label(Messages.Servers.listErrors.localized, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal)
                    .help(snapshot.errors.values.sorted().joined(separator: "\n"))
            }
            List(selection: $navigation.selectedID) {
                ForEach(filtered) { item in
                    HStack(alignment: .top, spacing: 10) {
                        ServerIcon(data: navigation.responses[item.id]?.icon ?? item.icon, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name).font(.headline).lineLimit(1)
                                if item.preference?.favorite == true { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                            }
                            Text(item.address.authority).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if !item.instanceIDs.isEmpty {
                                Text(model.state.instances.filter { item.instanceIDs.contains($0.id) }.prefix(2).map(\.name).joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(navigation.label(for: item.id)).font(.caption).foregroundStyle(navigation.failures[item.id] == nil ? Color.secondary : Color.orange).lineLimit(1)
                            if let response = navigation.responses[item.id] {
                                HStack {
                                    if let online = response.online { Label("\(online)/\(response.maximum.map(String.init) ?? "–")", systemImage: "person.2") }
                                    if let ping = response.latencyMilliseconds { Text(Messages.Servers.milliseconds(Int64(ping)).localized) }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 5).tag(item.id)
                }
            }.listStyle(.sidebar)
            .overlay {
                if navigation.snapshot == nil { ProgressView(Messages.Servers.loading.localized) }
                else if filtered.isEmpty { ContentUnavailableView(Messages.Servers.empty.localized, systemImage: "server.rack", description: Text(Messages.Servers.emptyDescription.localized)) }
            }
        }
        .navigationTitle(Messages.Servers.page.localized)
        .toolbar {
            Button { navigation.refreshID = UUID() } label: { Label(Messages.Servers.refresh.localized, systemImage: "arrow.clockwise") }
            Button { navigation.editor = .init(instanceID: navigation.instanceID) } label: { Label(Messages.Servers.add.localized, systemImage: "plus") }
                .disabled(model.readOnly || model.busy)
        }
        .task(id: "\(model.state.revision?.uuidString ?? "")/\(navigation.refreshID)/\(model.historyRevision)") {
            let paths = model.paths, state = model.state
            let observer = FileChangeObserver(directories: state.instances.map { paths.game($0.id) }, fallbackSeconds: 15)
            defer { observer.cancel() }
            await navigation.load(paths: paths, state: state)
            for await _ in observer.events {
                guard !Task.isCancelled else { break }
                await navigation.load(paths: paths, state: state)
            }
        }
        .task(id: filtered.map(\.id).joined(separator: "|") + navigation.refreshID.uuidString) {
            repeat {
                await navigation.refresh(filtered.map(\.address))
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            } while !Task.isCancelled
        }
        .onChange(of: filtered.map(\.id), initial: true) { _, ids in
            if navigation.selectedID.map(ids.contains) != true { navigation.selectedID = ids.first }
        }
    }
}

struct ServerIcon: View {
    let data: Data?
    var size: CGFloat = 64
    private var image: NSImage? { data.flatMap(ServerStatus.validatedIcon).flatMap(NSImage.init(data:)) }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.none).scaledToFit() }
            else { Image(systemName: "server.rack").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.secondary) }
        }.frame(width: size, height: size).background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.15))
    }
}

private struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    let item: ServerLibraryItem
    @Bindable var navigation: ServerNavigationState
    @State private var chosenInstance: UUID?
    private var response: ServerStatus? { navigation.responses[item.id] }
    private var instance: GameInstance? { model.state.instances.first { $0.id == chosenInstance } }
    private var needsAdd: Bool { chosenInstance.map { !item.instanceIDs.contains($0) } ?? true }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    ServerIcon(data: response?.icon ?? item.icon)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                        Text(item.address.authority).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        do {
                            var preference = item.preference ?? .init(address: item.address)
                            preference.favorite.toggle()
                            model.acceptState(try ServerLibrary.save(preference, paths: model.basePaths)); navigation.refreshID = UUID()
                        } catch { model.error = error.localizedDescription }
                    } label: { Image(systemName: item.preference?.favorite == true ? "star.fill" : "star") }
                        .help(Messages.Servers.favorite.localized).disabled(model.readOnly)
                    Button { navigation.editor = .init(item: item) } label: { Image(systemName: "slider.horizontal.3") }.help(Messages.Servers.globalSettings.localized)
                        .disabled(model.readOnly)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(navigation.label(for: item.id), systemImage: navigation.failures[item.id] == nil && response != nil ? "checkmark.circle.fill" : "network")
                            .foregroundStyle(navigation.failures[item.id] == nil ? Color.primary : Color.orange)
                        if let response {
                            if !response.description.isEmpty { Text(response.description).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            LabeledContent(Messages.Servers.version.localized, value: response.version ?? Messages.Servers.unknown.localized)
                            LabeledContent(Messages.Servers.players.localized, value: response.online.map { "\($0)/\(response.maximum.map(String.init) ?? "–")" } ?? Messages.Servers.unknown.localized)
                            LabeledContent(Messages.Servers.latency.localized, value: response.latencyMilliseconds.map { Messages.Servers.milliseconds(Int64($0)).localized } ?? Messages.Servers.unknown.localized)
                            LabeledContent(Messages.Servers.lastUpdated.localized) { Text(response.queriedAt, style: .relative) }
                        }
                        Text(Messages.Servers.queryHint.localized).font(.caption).foregroundStyle(.secondary)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Picker(Messages.Servers.chooseInstance.localized, selection: $chosenInstance) {
                        Text(Messages.Servers.chooseInstance.localized).tag(nil as UUID?)
                        ForEach(model.state.instances) { instance in Text(instance.name + " · " + instance.gameVersion).tag(Optional(instance.id)) }
                    }
                    if let instance, model.isInstanceInUse(instance.id) { Label(Messages.Servers.running.localized, systemImage: "lock") .font(.callout).foregroundStyle(.secondary) }
                    Button { join() } label: {
                        Label(needsAdd ? Messages.Servers.addAndJoin.localized : Messages.Servers.join.localized, systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(instance == nil || model.busy || model.readOnly || navigation.joining || instance.map { model.isInstanceInUse($0.id) } == true)
                }
                ServerHistorySection(address: item.address, summary: navigation.snapshot?.history[item.id], historyError: navigation.snapshot?.historyError)
                if !item.instanceIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Messages.Servers.instances.localized).font(.title3.weight(.semibold))
                        ForEach(model.state.instances.filter { item.instanceIDs.contains($0.id) }) { instance in
                            HStack { Text(instance.name); Spacer(); Button(Messages.Servers.manage.localized) { model.serverInstance = instance } }
                        }
                        if Set(item.instanceIDs.compactMap { navigation.snapshot?.lists[$0]?.directory }).count < item.instanceIDs.count {
                            Text(Messages.Servers.sharedDirectory.localized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let notes = item.preference?.notes, !notes.isEmpty { Text(notes).textSelection(.enabled) }
            }.padding(28).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onAppear {
            let preferred = item.preference?.preferredInstanceID
            chosenInstance = preferred.flatMap { id in model.state.instances.contains { $0.id == id } ? id : nil } ?? navigation.snapshot?.history[item.id]?.lastInstanceID.flatMap { id in model.state.instances.contains { $0.id == id } ? id : nil } ?? item.instanceIDs.first ?? model.selected?.id
        }
    }
    private func join() {
        guard let instance else { return }
        navigation.joining = true
        Task {
            defer { navigation.joining = false }
            do {
                let paths = model.paths, name = item.name, address = item.address, id = instance.id
                try await Task.detached(priority: .userInitiated) {
                    let manager = ServerListManager(paths: paths, instanceID: id), list = try manager.snapshot()
                    if !list.entries.contains(where: { $0.endpoint?.key == address.key }) { try manager.apply(.add(name: name, address: address, resourcePacks: .ask), to: list) }
                }.value
                navigation.refreshID = UUID()
                model.launch(instance, server: item.address)
            } catch { model.error = error.localizedDescription }
        }
    }
}
