import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

struct LocalContentDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: LocalContentFile
    @State private var matches: [ContentIdentity] = []
    @State private var loading = true
    @State private var failures: [String] = []
    @State private var attempt = 0
    @State private var curseforgeAvailable = true
    private var loaders: [String] { Array(Set((file.metadata?.loaders ?? []) + matches.flatMap(\.loaders).map { Self.loaderName($0) })).sorted() }
    private static func loaderName(_ value: String) -> String {
        switch value.lowercased() {
        case "fabric": "Fabric"
        case "quilt": "Quilt"
        case "forge": "Forge"
        case "neoforge": "NeoForge"
        case "liteloader": "LiteLoader"
        default: value
        }
    }
    private var source: String {
        switch file.managed?.installationSource ?? file.managed?.provider {
        case "modrinth": "Modrinth"
        case "curseforge": "CurseForge"
        default: Messages.ContentDetails.localFile.localized
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                LocalContentIcon(file: file, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(file.displayTitle).font(.title2.weight(.semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) { ForEach(loaders, id: \.self) { TagPill(text: $0) } }
                }
                Spacer(minLength: 0)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Messages.ContentDetails.description.localized).font(.headline)
                        Text(file.metadata?.summary ?? matches.compactMap(\.summary).first(where: { !$0.isEmpty }) ?? Messages.ContentDetails.noDescription.localized)
                            .font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox {
                        VStack(spacing: 10) {
                            field(Messages.ContentDetails.version.localized, file.version ?? "—")
                            if let id = file.modID { field(Messages.ContentDetails.modID.localized, id) }
                            if let authors = file.metadata?.authors, !authors.isEmpty { field(Messages.ContentDetails.authors.localized, authors.joined(separator: ", ")) }
                            field(Messages.ContentDetails.source.localized, source)
                            field(Messages.ContentDetails.size.localized, LocalizedFormat.bytes(file.size))
                            field(Messages.ContentDetails.filename.localized, file.filename)
                        }.frame(maxWidth: .infinity).padding(10)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(Messages.ContentDetails.onlineProjects.localized).font(.headline)
                            Spacer()
                            if loading { ProgressView().controlSize(.small) }
                            else { Button(Messages.ContentDetails.retry.localized, systemImage: "arrow.clockwise") { attempt += 1 }.buttonStyle(.borderless) }
                        }
                        if loading && matches.isEmpty {
                            Text(Messages.ContentDetails.lookingUp.localized).font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(matches) { match in
                            GroupBox {
                                HStack(spacing: 12) {
                                    CatalogIcon(url: match.iconURL, size: 36)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(match.record.title).font(.body.weight(.medium))
                                        Text(match.record.versionName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let url = match.pageURL, ["https", "http"].contains(url.scheme ?? "") {
                                        Link(destination: url) {
                                            Label(match.record.provider == "modrinth" ? "Modrinth" : "CurseForge", systemImage: "arrow.up.right.square")
                                        }
                                    }
                                }.padding(8)
                            }
                        }
                        if !loading, matches.isEmpty, failures.isEmpty {
                            Text(Messages.ContentDetails.noMatch.localized).font(.callout).foregroundStyle(.secondary)
                        }
                        if !curseforgeAvailable {
                            Text(Messages.ContentDetails.curseforgeUnavailable.localized).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(failures, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    }
                    HStack(spacing: 16) {
                        if let url = file.metadata?.homepage { Link(Messages.ContentDetails.homepage.localized, destination: url) }
                        if file.kind == .mod {
                            if let url = file.translation?.pageURL { Link(Messages.ContentDetails.encyclopedia.localized, destination: url) }
                            else if let url = encyclopediaSearch { Link(Messages.ContentDetails.searchEncyclopedia.localized, destination: url) }
                        }
                    }.font(.callout)
                    if file.translation != nil {
                        Text(Messages.ContentDetails.metadataAttribution.localized).font(.caption2).foregroundStyle(.tertiary)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Button(Messages.AppInstanceContentView.showInFinder.localized, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                Spacer()
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.borderedProminent)
            }.padding(20)
        }.frame(width: 620, height: 620)
            .task(id: attempt) { await identify() }
    }
    private var encyclopediaSearch: URL? {
        var url = URLComponents(string: "https://search.mcmod.cn/s")
        url?.queryItems = [.init(name: "key", value: file.title), .init(name: "site", value: "all"), .init(name: "filter", value: "0")]
        return url?.url
    }
    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout).accessibilityElement(children: .combine)
    }
    private func identify() async {
        loading = true; failures = []
        let key = try? CurseForgeKeyStore.load()
        curseforgeAvailable = key != nil
        let service = ContentIdentificationService(cacheDirectory: model.paths.cache, curseforge: key.map { CurseForgeService(apiKey: $0) })
        do {
            let result = try await service.identify([file], refresh: attempt > 0)
            try Task.checkCancellation()
            matches = result.matches[file.id] ?? []; failures = result.failures
        } catch { if !Task.isCancelled { failures = [error.localizedDescription] } }
        if !Task.isCancelled { loading = false }
    }
}
