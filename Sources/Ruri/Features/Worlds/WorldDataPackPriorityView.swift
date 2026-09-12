import RuriLocalization
import SwiftUI
import RuriCore

struct WorldDataPackPriorityView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    let world: WorldSnapshot
    @State private var snapshot: WorldDataPackPriority?
    @State private var keys: [String] = []
    @State private var error: String?
    private var manager: WorldManager { WorldManager(paths: model.paths, instanceID: instance.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: Messages.AppWorldDataPackPriorityView.bodyText1.localized, subtitle: world.name)
            Text(Messages.AppWorldDataPackPriorityView.bodyText2.localized).font(.callout).foregroundStyle(.secondary)
            if let snapshot {
                List {
                    ForEach(keys, id: \.self) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key == "vanilla" ? Messages.AppWorldDataPackPriorityView.snapshotText1.localized : key.hasPrefix("file/") ? String(key.dropFirst(5)) : key).lineLimit(1)
                                if !snapshot.localKeys.contains(key) { Text(key.hasPrefix("file/") ? Messages.AppWorldDataPackPriorityView.snapshotText2.localized : Messages.AppWorldDataPackPriorityView.snapshotText3.localized).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if snapshot.localKeys.contains(key), let index = keys.firstIndex(of: key) {
                                Button { keys.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.help(Messages.AppWorldDataPackPriorityView.indexText1.localized).disabled(index == 0 || model.busy)
                                Button { keys.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.help(Messages.AppWorldDataPackPriorityView.indexText2.localized).disabled(index + 1 == keys.count || model.busy)
                            }
                        }.padding(.vertical, 5)
                    }.onMove { indices, destination in
                        guard !model.busy, indices.allSatisfy({ snapshot.localKeys.contains(keys[$0]) }) else { return }
                        keys.move(fromOffsets: indices, toOffset: destination)
                    }
                }.listStyle(.bordered)
            } else if error == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange) }
            HStack {
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Spacer()
                Button(Messages.AppWorldDataPackPriorityView.errorText1.localized) { save() }.buttonStyle(.borderedProminent)
                    .disabled(snapshot == nil || keys == snapshot?.keys || model.busy || model.isInstanceInUse(instance.id))
            }
        }.padding(24).frame(width: 610, height: 520).interactiveDismissDisabled(model.busy)
        .task {
            do { let value = try await manager.dataPackPriority(folder: world.folder); snapshot = value; keys = value.keys }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        guard let snapshot else { return }
        model.perform(Messages.AppWorldDataPackPriorityView.snapshotText4, presentErrors: false, instanceID: instance.id) { _ in
            do { try await manager.setDataPackPriority(keys, folder: world.folder, expecting: snapshot); dismiss() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
}
