import SwiftUI
import RuriCore
import RuriLocalization

/// Shared by creation and component changes so filtering and compatibility stay
/// identical. The form remains compact; long histories live in a sized popover.
struct LoaderSelectionView: View {
    @Environment(AppModel.self) private var model
    let game: String
    @Binding var selections: [LoaderSelection]
    @Binding var isValid: Bool
    @State private var releases: [LoaderKind: [LoaderRelease]] = [:]
    @State private var errors: [LoaderKind: String] = [:]
    @State private var loadedGame = ""
    @State private var loading = false
    @State private var retry = 0

    private var kinds: [LoaderKind] { selections.map(\.loader) }
    private var issue: String? { LoaderCompatibility.combinationIssue(kinds, game: game) }
    private var valid: Bool {
        guard issue == nil else { return false }
        return selections.isEmpty || (!loading && loadedGame == game && selections.allSatisfy { selection in
            errors[selection.loader] == nil && available(selection.loader).contains { $0.version == selection.version }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Messages.AppCreateInstanceView.loader.localized).font(.headline)
                Spacer()
                Menu {
                    ForEach(LoaderKind.allCases.filter { $0 != .vanilla && !kinds.contains($0) }) { loader in
                        Button(loader.title) { selections.append(.init(loader: loader, version: "")) }
                            .disabled(LoaderCompatibility.combinationIssue(kinds + [loader], game: game) != nil)
                    }
                } label: { Label(Messages.LoaderSelection.addLoader.localized, systemImage: "plus") }
                    .fixedSize().disabled(game.isEmpty)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    if selections.isEmpty {
                        HStack {
                            Label(LoaderKind.vanilla.title, systemImage: LoaderKind.vanilla.symbol)
                            Spacer()
                            Text(Messages.LoaderSelection.noLoaders.localized).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                    ForEach(Array(selections.enumerated()), id: \.element.id) { index, selection in
                        if index > 0 { Divider().padding(.horizontal, 8) }
                        row(selection).padding(8)
                    }
                }
            }
            if !selections.isEmpty {
                Text(Messages.LoaderSelection.incompatibleChoicesHint.localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            ForEach(LoaderCompatibility.warnings(selections, game: game), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: valid, initial: true) { _, value in isValid = value }
        .task(id: game + ":" + kinds.map(\.rawValue).sorted().joined(separator: ",") + ":" + String(retry)) { await load() }
    }

    @ViewBuilder private func row(_ selection: LoaderSelection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(selection.loader.title, systemImage: selection.loader.symbol)
                Spacer(minLength: 12)
                if let release = available(selection.loader).first(where: { $0.version == selection.version }), release.channel != .stable {
                    Text(release.channel.title).font(.caption).foregroundStyle(.secondary)
                }
                if loading && releases[selection.loader] == nil { ProgressView().controlSize(.small) }
                LoaderVersionButton(loader: selection.loader, game: game, releases: available(selection.loader), version: Binding(
                    get: { selections.first { $0.loader == selection.loader }?.version ?? "" },
                    set: { value in if let index = selections.firstIndex(where: { $0.loader == selection.loader }) { selections[index].version = value } }
                ))
                .disabled(loading || releases[selection.loader] == nil)
                Button {
                    selections.removeAll { $0.loader == selection.loader }
                } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .help(Messages.LoaderSelection.removeComponent(selection.loader.title).localized)
                    .accessibilityLabel(Messages.LoaderSelection.removeComponent(selection.loader.title).localized)
            }
            if let error = errors[selection.loader] {
                HStack(alignment: .firstTextBaseline) {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(Messages.AppInstanceComponentsView.retry.localized) { releases[selection.loader] = nil; retry += 1 }.controlSize(.small)
                }
            } else if !loading, available(selection.loader).isEmpty {
                Text(Messages.AppInstanceComponentsView.noCompatibleLoader.localized).font(.caption).foregroundStyle(.orange)
            } else if !loading, !selection.version.isEmpty, !available(selection.loader).contains(where: { $0.version == selection.version }) {
                Text(Messages.LoaderSelection.versionUnavailable.localized).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func available(_ loader: LoaderKind) -> [LoaderRelease] {
        (releases[loader] ?? []).filter { !(loader == .optifine && kinds.contains(.forge) && $0.excludesForge) }
    }

    @MainActor private func load() async {
        loading = true
        let target = game
        if loadedGame != target {
            if !loadedGame.isEmpty { selections = selections.map { .init(loader: $0.loader, version: "") } }
            releases = [:]; errors = [:]; loadedGame = target
        }
        guard !target.isEmpty else { loading = false; return }
        for loader in kinds where releases[loader] == nil {
            do {
                let result = try await model.installer.loaderReleases(loader, game: target)
                try Task.checkCancellation()
                releases[loader] = result; errors[loader] = nil
            } catch {
                guard !Task.isCancelled else { return }
                errors[loader] = error.localizedDescription
            }
        }
        guard !Task.isCancelled else { return }
        for index in selections.indices where selections[index].version.isEmpty {
            selections[index].version = available(selections[index].loader).first?.version ?? ""
        }
        loading = false
    }
}

private struct LoaderVersionButton: View {
    let loader: LoaderKind
    let game: String
    let releases: [LoaderRelease]
    @Binding var version: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Text(version.isEmpty ? Messages.LoaderSelection.chooseVersion.localized : version).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help(Messages.LoaderSelection.chooseVersion.localized)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            LoaderVersionPopover(loader: loader, game: game, releases: releases, version: $version) { showing = false }
        }
    }
}

private struct LoaderVersionPopover: View {
    let loader: LoaderKind
    let game: String
    let releases: [LoaderRelease]
    @Binding var version: String
    let close: () -> Void
    @State private var search = ""
    @State private var channel = "stable"
    private var channels: [LoaderReleaseChannel] { LoaderReleaseChannel.allCases.filter { channel in releases.contains { $0.channel == channel } } }
    private var filtered: [LoaderRelease] {
        releases.filter { (channel == "all" || $0.channel.rawValue == channel) && (search.isEmpty || $0.version.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(loader.title).font(.headline)
                    Text(Messages.Discovery.minecraftVersion(game).localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.Common.done.localized, action: close).keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField(Messages.LoaderSelection.searchVersions.localized, text: $search).textFieldStyle(.roundedBorder)
                Picker(Messages.LoaderSelection.channel.localized, selection: $channel) {
                    Text(Messages.LoaderSelection.allChannels.localized).tag("all")
                    ForEach(channels) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().fixedSize()
            }
            List {
                ForEach(filtered) { release in
                    Button {
                        version = release.version; close()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: version == release.version ? "checkmark" : "circle")
                                .foregroundStyle(version == release.version ? Color.accentColor : Color.secondary.opacity(0.35))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(release.version).font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                                if let forge = release.forgeCompatibility, !forge.isEmpty {
                                    Text(Messages.LoaderSelection.forgeCompatibility(forge).localized).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(release.channel.title).font(.caption).foregroundStyle(.secondary)
                            if release.version == releases.first(where: { $0.channel == .stable })?.version {
                                Text(Messages.LoaderSelection.latestStable.localized).font(.caption).foregroundStyle(Color.accentColor)
                            }
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(version == release.version ? .isSelected : [])
                }
            }
            .listStyle(.bordered).frame(height: 240)
            .overlay { if filtered.isEmpty { Text(Messages.LoaderSelection.noMatchingVersions.localized).foregroundStyle(.secondary) } }
            if [.fabric, .quilt, .legacyfabric].contains(loader) {
                Text(Messages.LoaderSelection.universalVersionsHint.localized)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if loader == .optifine { Text(Messages.AppCreateInstanceView.optifineSource.localized).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(16).frame(width: 460)
        .onAppear { channel = releases.first(where: { $0.version == version })?.channel.rawValue ?? channels.first?.rawValue ?? "all" }
    }
}
