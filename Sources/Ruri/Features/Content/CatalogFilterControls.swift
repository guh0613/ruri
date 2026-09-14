import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogFilterLabel: View {
    let title: String
    let value: String
    let symbol: String
    var active = false
    var loader: String?
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let loader { LoaderGlyph.image(for: loader).resizable().scaledToFit().frame(width: 19, height: 19) }
                else { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
            }
                .foregroundStyle(active ? Theme.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .background(active ? Theme.accent.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.055) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Theme.accent.opacity(0.28) : Color.primary.opacity(0.075)))
        .contentShape(RoundedRectangle(cornerRadius: 10)).onHover { hovering = $0 }
        .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(value)
    }
}
struct CatalogMenuFilter<Content: View>: View {
    let title: String
    let value: String
    let symbol: String
    var active = false
    var loader: String?
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            CatalogFilterLabel(title: title, value: value, symbol: symbol, active: active, loader: loader)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help(title + " · " + value)
    }
}
struct CatalogLoaderFilter: View {
    @Binding var selection: String
    var loaders = ["fabric", "forge", "neoforge", "quilt", "legacy-fabric", "liteloader"]
    var body: some View {
        CatalogMenuFilter(title: D.loader.localized, value: selection.isEmpty ? D.unrestricted.localized : CatalogMetadata.loaderTitle(selection), symbol: "square.stack.3d.up", active: !selection.isEmpty, loader: selection.isEmpty ? nil : selection) {
            Picker(D.loader.localized, selection: $selection) {
                Label(D.allLoaders.localized, systemImage: "square.stack.3d.up").tag("")
                ForEach(Array(Set(loaders)).sorted(), id: \.self) { loader in
                    Label { Text(CatalogMetadata.loaderTitle(loader)) } icon: {
                        LoaderGlyph.image(for: loader).resizable().scaledToFit().frame(width: 16, height: 16)
                    }.tag(loader)
                }
            }.pickerStyle(.inline).labelsHidden().labelStyle(.titleAndIcon)
        }
    }
}
struct CatalogGameFilter: View {
    @Binding var selection: String
    let versions: [String]
    @State private var showing = false
    @State private var search = ""
    var body: some View {
        Button { search = ""; showing = true } label: {
            CatalogFilterLabel(title: D.gameVersion.localized, value: selection.isEmpty ? D.unrestricted.localized : selection, symbol: "cube", active: !selection.isEmpty)
        }
        .buttonStyle(.plain).help(D.gameVersion.localized)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Label(D.gameVersion.localized, systemImage: "cube").font(.headline)
                TextField(D.findGameVersion.localized, text: $search).textFieldStyle(.roundedBorder)
                    .onSubmit { let value = search.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { selection = value; showing = false } }
                ScrollView {
                    LazyVStack(spacing: 1) {
                        versionButton("", title: D.allGameVersions.localized)
                        ForEach(CatalogMetadata.sortedVersions(versions).filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { version in
                            versionButton(version, title: version)
                        }
                    }
                }.frame(height: 240)
                Text(D.customVersionHint.localized).font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(width: 250)
        }
    }
    private func versionButton(_ value: String, title: String) -> some View {
        Button { selection = value; showing = false } label: {
            HStack {
                Text(title); Spacer()
                if selection == value { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct CatalogInstanceFilterContext: View {
    let instance: GameInstance
    let clear: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(D.filteringForInstance(instance.name).localized).font(.callout.weight(.medium))
                Text(instance.subtitle).font(.caption).foregroundStyle(.secondary)
            }.textSelection(.enabled)
            Spacer(minLength: 8)
            Button(D.clearInstanceFilter.localized, action: clear).buttonStyle(.link).font(.callout)
        }
    }
}
