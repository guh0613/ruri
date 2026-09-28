import RuriLocalization
import SwiftUI
import RuriCore

/// Pinned instances and servers as a shelf of cards, each one click from
/// playing. Clicking a card opens it in the library or the server center.
struct HomePinnedSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appearsActive) private var appearsActive
    let instances: [GameInstance]
    @Bindable var servers: ServerNavigationState
    private var pinnedServers: [ServerLibraryItem] { servers.snapshot?.items.filter { $0.preference?.favorite == true } ?? [] }
    private var hasPinnedServers: Bool { model.state.servers?.contains(where: \.favorite) == true }
    private var statusKey: String { pinnedServers.map(\.id).joined(separator: "|") }

    var body: some View {
        Group {
            if !instances.isEmpty || !pinnedServers.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(Messages.AppHomeView.pinned.localized)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(instances) { instance in instanceCard(instance) }
                        ForEach(pinnedServers) { item in serverCard(item) }
                    }
                }
            }
        }
        // Server names and icons come from the instances' multiplayer lists,
        // so the library is read only while something is pinned.
        .task(id: "\(model.state.revision?.uuidString ?? "")/\(servers.refreshID)/\(model.historyRevision)/\(hasPinnedServers)") {
            guard hasPinnedServers else { servers.snapshot = nil; return }
            await servers.load(paths: model.paths, state: model.state)
        }
        .task(id: "\(statusKey)|\(appearsActive)") {
            guard appearsActive, !pinnedServers.isEmpty else { return }
            await servers.monitor(pinnedServers.map(\.address), key: statusKey)
        }
    }

    // MARK: Instances

    private func instanceCard(_ instance: GameInstance) -> some View {
        PinnedCard(openTitle: Messages.AppHomeView.showInLibrary.localized, open: { model.showInstance(instance) }) {
            InstanceIcon(instance, size: 44)
        } title: {
            Text(instance.name)
        } subtitle: {
            Text(instance.gameVersion + " · " + instance.loaderLabel)
        } action: {
            LaunchButton(instance: instance, compact: true)
        }
        .contextMenu {
            Group {
                Button(Messages.AppHomeView.showInLibrary.localized, systemImage: "square.grid.2x2") { model.showInstance(instance) }
                InstancePinButton(instance: instance)
                Divider()
                Button(Messages.AppHomeView.instanceSettings.localized, systemImage: "slider.horizontal.3") { model.editingInstance = instance }
                Button(Messages.AppHomeView.showInFinder.localized, systemImage: "folder") { model.reveal(instance) }
            }.labelStyle(.titleAndIcon)
        }
    }

    // MARK: Servers

    private func serverCard(_ item: ServerLibraryItem) -> some View {
        let reachability = servers.reachability(item.id)
        return PinnedCard(openTitle: Messages.Servers.showInServers.localized, open: { model.showServer(item.address) }) {
            ServerIcon(data: reachability.status?.icon ?? item.icon, size: 44)
        } title: {
            Text(item.name)
        } subtitle: {
            HStack(spacing: 5) {
                ServerSignal(reachability: reachability)
                Text(serverSummary(item, reachability))
            }
        } action: {
            ServerJoinButton(item: item, navigation: servers)
        }
        .contextMenu {
            Group {
                Button(Messages.Servers.showInServers.localized, systemImage: "server.rack") { model.showServer(item.address) }
                Button(Messages.Servers.unfavorite.localized, systemImage: "pin.slash") { servers.toggleFavorite(item, model: model) }
                    .disabled(model.readOnly)
                Divider()
                Button(Messages.Servers.copyAddress.localized, systemImage: "doc.on.doc") { copyServerAddress(item.address) }
            }.labelStyle(.titleAndIcon)
        }
    }

    private func serverSummary(_ item: ServerLibraryItem, _ reachability: ServerReachability) -> String {
        switch reachability {
        case .online(let status):
            [status.playersLabel, status.latencyMilliseconds.map { Messages.Servers.milliseconds(Int64($0)).localized }].compactMap { $0 }.joined(separator: " · ")
        case .offline: Messages.Servers.offline.localized
        case .unknown, .querying: item.address.authority
        }
    }
}

/// Joins the server with the instance it would use from the server center,
/// or returns to that instance's game while it is running.
private struct ServerJoinButton: View {
    @Environment(AppModel.self) private var model
    let item: ServerLibraryItem
    let navigation: ServerNavigationState
    var body: some View {
        let instance = navigation.defaultInstance(for: item, model: model)
        let running = instance.map { model.activeSessions[$0.id] != nil } == true
        let disabled = instance == nil || navigation.joining || (!running && (model.busy || model.readOnly || instance.map { model.isInstanceInUse($0.id) } == true))
        let title = instance.map { Messages.Servers.joinButton.localized + " · " + $0.name } ?? Messages.Servers.noInstance.localized
        Button { if let instance { navigation.join(item, with: instance, model: model) } } label: {
            Image(systemName: running ? "arrow.up.forward.circle.fill" : "play.circle.fill")
                .font(.system(size: 30)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Theme.accent))
                .accessibilityLabel(title)
        }
        .buttonStyle(.plain).help(title).disabled(disabled)
    }
}

/// A compact card with an icon, two lines of text and a trailing play button.
private struct PinnedCard<Icon: View, Title: View, Subtitle: View, Action: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let openTitle: String
    let open: () -> Void
    @ViewBuilder var icon: Icon
    @ViewBuilder var title: Title
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var action: Action
    @State private var hovering = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                title.font(.headline).lineLimit(1)
                subtitle.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(shape)
        .onTapGesture(perform: open)
        .background {
            shape.fill(Theme.surface(for: colorScheme))
                .overlay { shape.fill(.primary.opacity(hovering ? 0.045 : 0)) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, x: 0, y: 3)
        }
        .overlay {
            shape.strokeBorder(.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1).allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .help(openTitle)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(openTitle), open)
    }
}
