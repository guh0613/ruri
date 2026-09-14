import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogVersionGroup: View {
    let title: String
    let versions: [CatalogVersion]
    @Binding var isExpanded: Bool
    let canAcquire: Bool
    let onDetails: (CatalogVersion) -> Void
    let onAcquire: (CatalogVersion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 12).accessibilityHidden(true)
                    Text(title).font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(CatalogButtonStyle())
            .background(.primary.opacity(0.025))
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? D.groupExpanded.localized : D.groupCollapsed.localized)
            .help(isExpanded ? D.collapseGroup.localized : D.expandGroup.localized)
            if isExpanded {
                Divider()
                ForEach(versions) { version in
                    CatalogReleaseRow(version: version, canAcquire: canAcquire,
                                      onDetails: { onDetails(version) }, onAcquire: { onAcquire(version) })
                    if version.id != versions.last?.id {
                        Divider().padding(.horizontal, 18)
                    }
                }
            }
        }
    }
}

struct CatalogReleaseRow: View {
    let version: CatalogVersion
    let canAcquire: Bool
    let onDetails: () -> Void
    let onAcquire: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onDetails) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TagPill(text: version.channel == "release" ? D.release.localized : version.channel.capitalized,
                                color: version.channel == "release" ? .green : .orange)
                        Text(version.name).font(.headline).lineLimit(2)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    WrappingLayout(spacing: 12) {
                        CatalogCompatibilityLine(versions: version.gameVersions, loaders: version.loaders)
                        Text([LocalizedFormat.publishedDate(version.published), LocalizedFormat.bytes(version.size)].joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CatalogButtonStyle())
            .help(D.fileDetails.localized + " · " + version.filename)
            .accessibilityHint(D.fileDetails.localized)

            Button(action: onAcquire) {
                Label(D.installOrSave.localized, systemImage: "arrow.down.circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(CatalogButtonStyle())
            .foregroundStyle(canAcquire ? Theme.accent : Color.secondary)
            .disabled(!canAcquire)
            .help(D.installOrSave.localized)
            .accessibilityLabel(D.installOrSave.localized + " · " + version.name)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .contextMenu {
            Button(D.fileDetails.localized, action: onDetails)
            Button(D.installOrSave.localized, action: onAcquire).disabled(!canAcquire)
        }
        .accessibilityElement(children: .contain)
    }
}
