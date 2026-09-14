import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogReleaseInfo: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: CatalogProject
    let version: CatalogVersion
    let onOpenProject: (CatalogProject) -> Void
    @State private var tab = "dependencies"
    @State private var changelog: String?
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(version.name).font(.title2.weight(.semibold))
                    Text(version.filename).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    WrappingLayout(spacing: 6) {
                        CatalogGameVersionsBadge(versions: version.gameVersions)
                        if !version.loaders.isEmpty { CatalogLoaderBadges(loaders: version.loaders) }
                    }
                }
                Spacer()
                Button(D.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker(D.fileDetails.localized, selection: $tab) {
                Text(D.dependencies.localized).tag("dependencies")
                Text(D.changelog.localized).tag("changelog")
            }.pickerStyle(.segmented).labelsHidden()
            if tab == "dependencies" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if version.dependencies.isEmpty { ContentUnavailableView(D.noDependencies.localized, systemImage: "shippingbox").frame(maxWidth: .infinity) }
                        else {
                            Text(D.dependencyVersionNotice.localized).font(.callout).foregroundStyle(.secondary)
                            ForEach(version.dependencies) { dependency in
                                CatalogDependencyRow(dependency: dependency, onOpen: onOpenProject)
                            }
                        }
                    }
                }
            } else if let changelog {
                if changelog.isEmpty { ContentUnavailableView(D.noChangelog.localized, systemImage: "text.alignleft") }
                else { CatalogDocumentView(text: changelog, isHTML: project.source == .curseforge, baseURL: project.pageURL).clipShape(RoundedRectangle(cornerRadius: 10)) }
            } else if let error { CatalogErrorBanner(message: error) { retry += 1 }; Spacer() }
            else { ProgressView(D.loadingChangelog.localized).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.padding(24).frame(width: 630, height: 520)
        .task(id: "\(tab):\(retry)") {
            guard tab == "changelog", changelog == nil else { return }
            error = nil
            do { let text = try await model.catalogRepository.changelog(version); try Task.checkCancellation(); changelog = text }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
struct CatalogDependencyRow: View {
    @Environment(AppModel.self) private var model
    let dependency: CatalogDependency
    let onOpen: (CatalogProject) -> Void
    @State private var project: CatalogProject?
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        HStack(spacing: 12) {
            CatalogIcon(url: project?.icon, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(project?.title ?? dependency.projectID ?? dependency.versionID ?? D.unknownDependency.localized).font(.headline)
                HStack(spacing: 6) {
                    Text(dependency.title)
                    if dependency.versionID != nil { Text(D.pinnedVersion.localized) }
                }.font(.caption).foregroundStyle(dependency.relation == "incompatible" ? .orange : .secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if let project { Button(D.viewProject.localized) { onOpen(project) } }
            else if error != nil { Button(Messages.AppDiscoverView.retry.localized) { retry += 1 } }
            else { ProgressView().controlSize(.small) }
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .task(id: retry) {
            error = nil
            do { let result = try await model.catalogRepository.dependency(dependency); try Task.checkCancellation(); project = result }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
