import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CurseForgePlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: CurseForgeContentPlan
    @State private var manualFiles: [Int: URL] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: Messages.AppCurseForgeInstallView.updatePack(plan.title).localized, subtitle: Messages.AppCurseForgeInstallView.updateSummary(plan.instance.name, Int64(plan.files.count)).localized)
            ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(maxHeight: 360)
            HStack { Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(Messages.AppCurseForgeInstallView.update.localized) { model.installCurseForge(plan, manualFiles: manualFiles); dismiss() }.buttonStyle(.borderedProminent).disabled(model.busy || model.isInstanceInUse(plan.instance.id) || !plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil }) }
        }.padding(26).frame(width: 570)
    }
}
