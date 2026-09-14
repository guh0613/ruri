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
        HStack(spacing: 7) {
            Group {
                if let loader { LoaderGlyph.image(for: loader).resizable().scaledToFit() }
                else { Image(systemName: symbol).resizable().scaledToFit() }
            }
            .frame(width: 14, height: 14)
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary).fixedSize()
            Text(value).foregroundStyle(.primary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10).frame(height: 34)
        .background(active ? Theme.accent.opacity(0.07) : Color.primary.opacity(hovering ? 0.06 : 0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Theme.accent.opacity(0.25) : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 8)).onHover { hovering = $0 }
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
