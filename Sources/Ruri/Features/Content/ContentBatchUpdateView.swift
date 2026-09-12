import RuriLocalization
import SwiftUI
import RuriCore

struct ContentBatchUpdateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: ContentBatchUpdatePlan
    @State private var manualFiles: [Int: URL] = [:]
    private var missingManualFiles: Bool { plan.curseforge.contains { $0.requiresManualDownload && manualFiles[$0.id] == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: Messages.AppContentBatchUpdateView.bodyText1(Int64(plan.selectedIDs.count)).localized, subtitle: plan.instance.name)
            Text(Messages.AppContentBatchUpdateView.bodyText2(Int64(plan.records.count), String(describing: LocalizedFormat.bytes(plan.downloadSize))).localized).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(plan.records) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.title).font(.headline)
                                Spacer()
                                if !plan.selectedIDs.contains(record.id) { TagPill(text: Messages.AppContentBatchUpdateView.bodyText3.localized) }
                            }
                            if let previous = plan.baseline.first(where: { $0.id == record.id }) {
                                Text(previous.versionName + " → " + record.versionName).font(.callout)
                                if !previous.enabled { Text(Messages.AppContentBatchUpdateView.previousText1.localized).font(.caption).foregroundStyle(.secondary) }
                            } else { Text(Messages.AppContentBatchUpdateView.previousVersion(record.versionName).localized).font(.callout) }
                            Text(record.filename).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Divider()
                    }
                    let manual = plan.curseforge.filter(\.requiresManualDownload)
                    if !manual.isEmpty { CurseForgePlanFiles(files: manual, manualFiles: $manualFiles) }
                }
            }
            Text(Messages.AppContentBatchUpdateView.manualText1.localized).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(Messages.AppContentBatchUpdateView.manualText2(Int64(plan.selectedIDs.count)).localized) {
                    model.perform(Messages.AppContentBatchUpdateView.manualText3(Int64(plan.selectedIDs.count)), instanceID: plan.instance.id) { id in
                        try await ContentBatchUpdater(curseforge: CurseForgeService(apiKey: "")).install(plan, paths: model.paths, downloader: model.installer.downloader, manualFiles: manualFiles) { p in await model.progress(id, p) }
                        model.notice = Messages.AppContentBatchUpdateView.manualText4(Int64(plan.selectedIDs.count)).localized
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(model.busy || model.isInstanceInUse(plan.instance.id) || missingManualFiles)
            }
        }.padding(24).frame(width: 600, height: 570)
    }
}
