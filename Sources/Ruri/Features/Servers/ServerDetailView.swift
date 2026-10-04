import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

/// The server chosen in the server center, laid out like an instance in the
/// library: a header washed with the server's icon and the join control, a
/// strip of the numbers players check, what the server says about itself,
/// and how play on it went.
struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let item: ServerLibraryItem
    @Bindable var navigation: ServerNavigationState
    @State private var chosenInstance: UUID?
    private var reachability: ServerReachability { navigation.reachability(item.id) }
    private var response: ServerStatus? { navigation.responses[item.id] }
    private var querying: Bool { navigation.querying.contains(item.id) }
    private var summary: ServerPlaySummary? { navigation.snapshot?.history[item.id] }
    private var icon: Data? { response?.icon ?? item.icon }
    private var pinned: Bool { item.preference?.favorite == true }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(topInset: geometry.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 32) {
                        FactStrip(items: stripItems)
                        statusSection
                        ServerHistorySection(address: item.address, summary: summary, historyError: navigation.snapshot?.historyError)
                        instancesSection
                        if let notes = item.preference?.notes.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                            notesSection(notes)
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 32)
                    .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
                }
                .background { OverlayScrollIndicators().allowsHitTesting(false).accessibilityHidden(true) }
            }
            .ignoresSafeArea(.container, edges: .top)
            // Let the artwork reach the title bar, but keep the scroller below it.
            .contentMargins(.top, geometry.safeAreaInsets.top + 8, for: .scrollIndicators)
            .contentMargins(.bottom, 8, for: .scrollIndicators)
            .softTopScrollEdge()
        }
        .onAppear { chosenInstance = navigation.defaultInstance(for: item, model: model)?.id }
        .onChange(of: model.state.instances.map(\.id)) { _, ids in
            if chosenInstance.map(ids.contains) != true { chosenInstance = navigation.defaultInstance(for: item, model: model)?.id }
        }
    }

    // MARK: Header

    private func hero(topInset: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) { identity; Spacer(minLength: 16); actions }
            VStack(alignment: .leading, spacing: 18) { identity; actions }
        }
        .padding(.horizontal, 28).padding(.top, 64 + topInset).padding(.bottom, 28)
        .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        .background { backdrop.clipped().accessibilityHidden(true) }
    }

    /// A soft wash of the server's icon, or of the accent when it has none.
    private var backdrop: some View {
        let canvas = Theme.canvas(for: colorScheme)
        return ZStack {
            canvas
            if let data = icon.flatMap(ServerStatus.validatedIcon), let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
                    .blur(radius: 60, opaque: true).saturation(1.4)
                    .opacity(colorScheme == .dark ? 0.55 : 0.4)
            } else {
                Theme.accent.opacity(colorScheme == .dark ? 0.16 : 0.10)
            }
            LinearGradient(colors: [canvas.opacity(0), canvas], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
        }
    }

    private var identity: some View {
        HStack(spacing: 20) {
            ServerIcon(data: icon, size: 96)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(.system(size: 30, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(item.address.authority).font(.callout.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button { copyServerAddress(item.address) } label: { Image(systemName: "doc.on.doc").font(.caption) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(Messages.Servers.copyAddress.localized).accessibilityLabel(Messages.Servers.copyAddress.localized)
                }
                statusLine
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            ServerSignal(reachability: querying && response == nil ? .querying : reachability)
            Text(reachability.summary)
                .foregroundStyle(reachability.status == nil && navigation.failures[item.id] != nil ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
        .font(.callout)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            PinToggleButton(pinned: pinned) { navigation.toggleFavorite(item, model: model) }.disabled(model.readOnly)
            circleAction("slider.horizontal.3", Messages.Servers.globalSettings.localized) {
                navigation.editor = .init(item: item, status: response)
            }.disabled(model.readOnly)
            Menu {
                Group {
                    Button(Messages.Servers.copyAddress.localized, systemImage: "doc.on.doc") { copyServerAddress(item.address) }
                    Button(Messages.Servers.refreshStatus.localized, systemImage: "arrow.clockwise") { Task { await navigation.refresh(item.address) } }
                        .disabled(querying)
                    if let instance = selectedInstance {
                        Divider()
                        Button(Messages.Servers.manage.localized + " · " + instance.name, systemImage: "list.bullet") { model.serverInstance = instance }
                    }
                    if item.preference?.saved == true {
                        Divider()
                        Button(Messages.Servers.removeFromLibrary.localized, systemImage: "trash", role: .destructive) { navigation.removeTarget = item }
                            .disabled(model.readOnly)
                    }
                }.labelStyle(.titleAndIcon)
            } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(Messages.Servers.moreActions.localized).accessibilityLabel(Messages.Servers.moreActions.localized)
            ServerJoinControl(item: item, navigation: navigation, chosenInstance: $chosenInstance)
        }
        .fixedSize()
    }

    private var selectedInstance: GameInstance? { model.state.instances.first { $0.id == chosenInstance } }

    private func circleAction(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18) }
            .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large)
            .help(title).accessibilityLabel(title)
    }

    // MARK: Numbers

    private var stripItems: [FactStripItem] {
        let pending = querying && response == nil ? "…" : "—"
        return [
            FactStripItem(id: "players", label: Messages.Servers.players.localized,
                          value: response?.online.map(LocalizedFormat.number) ?? pending,
                          detail: response?.maximum.map { Messages.Servers.maximumPlayers(Int64($0)).localized }),
            FactStripItem(id: "latency", label: Messages.Servers.latency.localized,
                          value: response?.latencyMilliseconds.map { Messages.Servers.milliseconds(Int64($0)).localized } ?? pending),
            FactStripItem(id: "version", label: Messages.Servers.version.localized, value: response?.version ?? pending,
                          detail: response?.protocolVersion.map { Messages.Servers.protocolVersion(Int64($0)).localized }),
            FactStripItem(id: "playtime", label: Messages.Servers.playtime.localized,
                          value: summary.map { LocalizedFormat.duration($0.seconds) } ?? Messages.Servers.notPlayed.localized,
                          detail: summary.map { Messages.Servers.visitCount(Int64($0.visits)).localized }),
            FactStripItem(id: "lastPlayed", label: Messages.Servers.lastPlayed.localized,
                          value: summary.map { LocalizedFormat.relative($0.lastPlayed) } ?? "—",
                          detail: summary.map { LocalizedFormat.date($0.lastPlayed, time: .omitted) }),
        ]
    }

    // MARK: Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.Servers.statusSection.localized) {
                HStack(spacing: 12) {
                    if let response { Text(Messages.Servers.updatedAt(LocalizedFormat.relative(response.queriedAt)).localized).foregroundStyle(.secondary) }
                    if querying {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { Task { await navigation.refresh(item.address) } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                            .help(Messages.Servers.refreshStatus.localized).accessibilityLabel(Messages.Servers.refreshStatus.localized)
                    }
                }
            }
            Surface(padding: 0) {
                switch reachability {
                case .online(let status): statusCard(status)
                case .offline(let error): offlineCard(error)
                case .querying, .unknown: DelayedProgressView().frame(maxWidth: .infinity, minHeight: 88)
                }
            }
        }
    }

    /// Minecraft pads the message of the day with spaces to center it in the
    /// game's own font; in the system font that only reads as stray indents.
    private func motd(_ status: ServerStatus) -> String {
        status.description.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func statusCard(_ status: ServerStatus) -> some View {
        let text = motd(status)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if text.isEmpty { Text(Messages.Servers.noDescription.localized).foregroundStyle(.secondary) }
                else { Text(text).font(.body).lineSpacing(3).textSelection(.enabled) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            if !status.playerSample.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(Messages.Servers.onlinePlayers.localized).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    WrappingLayout(spacing: 6) {
                        ForEach(Array(status.playerSample.prefix(24).enumerated()), id: \.offset) { _, name in
                            MetadataBadge(text: name, symbol: "person.fill", compact: true)
                        }
                        if let online = status.online, online > min(status.playerSample.count, 24) {
                            Text(Messages.Servers.morePlayers(Int64(online - min(status.playerSample.count, 24))).localized)
                                .font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
    }

    private func offlineCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "network.slash").font(.system(size: 22)).foregroundStyle(.red).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(Messages.Servers.offline.localized).font(.headline)
                Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(Messages.Servers.queryHint.localized).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            Spacer(minLength: 8)
            Button(Messages.Servers.retry.localized) { Task { await navigation.refresh(item.address) } }.disabled(querying)
        }
        .padding(20)
    }

    // MARK: Instances

    private var listedInstances: [GameInstance] { model.state.instances.filter { item.instanceIDs.contains($0.id) } }

    private var instancesSection: some View {
        let instances = listedInstances
        let shared = Set(item.instanceIDs.compactMap { navigation.snapshot?.lists[$0]?.directory }).count < item.instanceIDs.count
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.Servers.instances.localized)
            Surface(padding: 0) {
                if instances.isEmpty {
                    Text(Messages.Servers.notInInstances.localized).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(instances) { instance in
                            ServerInstanceRow(instance: instance, preferred: item.preference?.preferredInstanceID == instance.id) { model.serverInstance = instance }
                            if instance.id != instances.last?.id { Divider().padding(.leading, 58) }
                        }
                    }
                }
            }
            if shared { Text(Messages.Servers.sharedDirectory.localized).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.Servers.notes.localized) {
                SectionLink(Messages.Servers.edit.localized) { navigation.editor = .init(item: item, status: response) }
                    .disabled(model.readOnly)
            }
            Surface {
                Text(notes).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A pop-up of instances next to the prominent join button, like the scheme
/// menu beside Run in Xcode. Instances that already list the server come first.
private struct ServerJoinControl: View {
    @Environment(AppModel.self) private var model
    let item: ServerLibraryItem
    @Bindable var navigation: ServerNavigationState
    @Binding var chosenInstance: UUID?
    private var instance: GameInstance? { model.state.instances.first { $0.id == chosenInstance } }
    private var needsAdd: Bool { chosenInstance.map { !item.instanceIDs.contains($0) } ?? false }
    private var session: GameSession? { instance.flatMap { model.activeSessions[$0.id] } }
    var body: some View {
        HStack(spacing: 8) {
            if !model.state.instances.isEmpty {
                let listed = model.state.instances.filter { item.instanceIDs.contains($0.id) }
                let others = model.state.instances.filter { !item.instanceIDs.contains($0.id) }
                Picker(Messages.Servers.chooseInstance.localized, selection: $chosenInstance) {
                    if listed.isEmpty || others.isEmpty {
                        ForEach(model.state.instances) { option($0) }
                    } else {
                        Section(Messages.Servers.listedInstances.localized) { ForEach(listed) { option($0) } }
                        Section(Messages.Servers.otherInstances.localized) { ForEach(others) { option($0) } }
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                .help(Messages.Servers.instanceMenuHelp.localized)
            }
            if let session, let instance {
                Button { model.returnToGame(instance.id) } label: {
                    Label(session.gameIdentity?.isAlive == true ? Messages.AppLaunchButton.returnToGame.localized : Messages.AppLaunchButton.viewRunHistory.localized,
                          systemImage: "arrow.up.forward.app").padding(.horizontal, 6)
                }.buttonStyle(.borderedProminent)
            } else {
                Button { if let instance { navigation.join(item, with: instance, model: model) } } label: {
                    Label(needsAdd ? Messages.Servers.addAndJoinButton.localized : Messages.Servers.joinButton.localized, systemImage: "play.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(instance == nil || navigation.joining || model.busy || model.readOnly || instance.map { model.isInstanceInUse($0.id) } == true)
                .help(instance == nil ? Messages.Servers.noInstance.localized : needsAdd ? Messages.Servers.addAndJoinHelp.localized : Messages.Servers.joinHelp.localized)
            }
        }
        .controlSize(.large)
    }
    private func option(_ instance: GameInstance) -> some View {
        Text(instance.name + " · " + instance.gameVersion).tag(Optional(instance.id))
    }
}

private struct ServerInstanceRow: View {
    let instance: GameInstance
    let preferred: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                InstanceIcon(instance, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(instance.name).font(.callout.weight(.medium)).lineLimit(1)
                        if preferred { TagPill(text: Messages.Servers.preferredInstance.localized) }
                    }
                    Text(instance.gameVersion + " · " + instance.loaderLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Messages.Servers.manageList.localized).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.primary.opacity(hovering ? 0.045 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Messages.Servers.manage.localized)
    }
}
