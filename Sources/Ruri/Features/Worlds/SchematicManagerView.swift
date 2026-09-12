import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct SchematicManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var directory = ""
    @State private var entries: [SchematicEntry] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false
    @State private var importing = false
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var removing: SchematicEntry?
    @State private var inspecting: SchematicEntry?
    private var manager: SchematicManager { SchematicManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !loading && !model.busy && !model.isInstanceInUse(instance.id) }
    private var types: [UTType] { SchematicManager.fileExtensions.map { UTType(filenameExtension: $0) ?? .data } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: Messages.AppSchematicManagerView.schematics.localized, subtitle: instance.name)
                Spacer()
                Button(Messages.AppSchematicManagerView.newFolder.localized, systemImage: "folder.badge.plus") { folderName = ""; creatingFolder = true }.disabled(!canModify)
                Button(Messages.AppSchematicManagerView.importSchematics.localized, systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
            Text(Messages.AppSchematicManagerView.schematicHelp.localized).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { directory = directory.split(separator: "/").dropLast().joined(separator: "/"); search = "" } label: { Image(systemName: "chevron.left") }.disabled(directory.isEmpty || model.busy).help(Messages.AppSchematicManagerView.goUp.localized)
                Button("schematics") { directory = ""; search = "" }.disabled(directory.isEmpty || model.busy)
                if !directory.isEmpty { Text("/ " + directory).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }
                Spacer()
                TextField(Messages.AppSchematicManagerView.searchFolder.localized, text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                List(entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "square.3.layers.3d").font(.title2).foregroundStyle(Theme.accent)
                        Button {
                            if entry.isDirectory { directory = entry.id; search = "" } else { inspecting = entry }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.name).font(.headline).lineLimit(1)
                                if !entry.isDirectory { Text(entry.url.pathExtension.uppercased() + " · " + LocalizedFormat.bytes(entry.size)).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.busy)
                        Menu {
                            if !entry.isDirectory { Button(Messages.AppSchematicManagerView.viewInfo.localized) { inspecting = entry }; Button(Messages.AppSchematicManagerView.exportSchematics.localized) { export(entry) }.disabled(!canModify) }
                            Button(Messages.AppSchematicManagerView.revealInFinder.localized) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                            Divider()
                            Button(Messages.AppSchematicManagerView.trashSchematics.localized, role: .destructive) { removing = entry }.disabled(!canModify)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(.vertical, 7)
                }.listStyle(.bordered)
                .overlay { if entries.isEmpty { Text(Messages.AppSchematicManagerView.dropSchematics.localized).foregroundStyle(.secondary).allowsHitTesting(false) } }
                .dropDestination(for: URL.self) { urls, _ in guard canModify else { return false }; importFiles(urls); return true }
            }
            HStack {
                Button(Messages.AppSchematicManagerView.refresh.localized, systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(loading || model.busy)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button(Messages.AppSchematicManagerView.cancelTask.localized) { model.operation?.cancel() } }
            }
        }.padding(24).frame(width: 780, height: 600).interactiveDismissDisabled(model.busy)
        .task(id: directory) { await reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: types, allowsMultipleSelection: true) { result in
            do { importFiles(try result.get()) } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $inspecting) { entry in SchematicInfoView(entry: entry, manager: manager) }
        .alert(Messages.AppSchematicManagerView.newFolder.localized, isPresented: $creatingFolder) {
            TextField(Messages.AppSchematicManagerView.folderName.localized, text: $folderName)
            Button(Messages.AppSchematicManagerView.createFolder.localized) { mutate(Messages.AppSchematicManagerView.newSchematicFolder.localized) { try await manager.createFolder(folderName, directory: directory) } }
            Button(Messages.Common.cancel.localized, role: .cancel) {}
        }
        .confirmationDialog(Messages.AppSchematicManagerView.confirmTrash.localized, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(Messages.AppSchematicManagerView.trash.localized, role: .destructive) {
                if let entry = removing { mutate(Messages.AppSchematicManagerView.entryRemoval.localized) { _ = try await manager.remove(entry) } }
                removing = nil
            }
        } message: { Text((removing?.name ?? "") + (removing?.isDirectory == true ? Messages.AppSchematicManagerView.entryFiles.localized : "")) }
    }
    private func importFiles(_ urls: [URL]) {
        mutate(Messages.AppSchematicManagerView.importSchematicFiles.localized) {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }; defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            try await manager.importFiles(urls, directory: directory)
        }
    }
    private func export(_ entry: SchematicEntry) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.name
        panel.allowedContentTypes = [UTType(filenameExtension: entry.url.pathExtension) ?? .data]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        mutate(Messages.AppSchematicManagerView.exportDestination.localized) { try await manager.export(entry, to: destination); model.notice = Messages.AppSchematicManagerView.exportedSchematic.localized; model.noticeFileURL = destination }
    }
    private func reload() async {
        loading = true; error = nil
        do { let value = try await manager.list(directory: directory); try Task.checkCancellation(); entries = value }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
    private func mutate(_ title: String, action: @MainActor @Sendable @escaping () async throws -> Void) {
        guard canModify else { return }; error = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { _ in
            do { try await action(); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
}

private struct SchematicInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: SchematicEntry
    let manager: SchematicManager
    @State private var info: SchematicInfo?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: info?.name?.isEmpty == false ? info!.name! : entry.name, subtitle: entry.name)
            if let info {
                if let data = info.previewARGB, let preview = image(data) { Image(nsImage: preview).resizable().interpolation(.none).scaledToFit().frame(maxWidth: .infinity, maxHeight: 160) }
                if let description = info.description, !description.isEmpty { Text(description).font(.callout).textSelection(.enabled) }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    if let author = info.author, !author.isEmpty { row(Messages.AppSchematicManagerView.author.localized, author) }
                    if !info.dimensions.isEmpty { row(Messages.AppSchematicManagerView.size.localized, info.dimensions.map(String.init).joined(separator: " × ")) }
                    if let blocks = info.blocks { row(Messages.AppSchematicManagerView.blocks.localized, LocalizedFormat.number(blocks)) }
                    if let volume = info.volume { row(Messages.AppSchematicManagerView.volume.localized, LocalizedFormat.number(volume)) }
                    if let regions = info.regions { row(Messages.AppSchematicManagerView.regions.localized, LocalizedFormat.number(regions)) }
                    if let version = info.formatVersion { row(Messages.AppSchematicManagerView.formatVersion.localized, String(version)) }
                    if let version = info.gameDataVersion { row(Messages.AppSchematicManagerView.gameDataVersion.localized, String(version)) }
                    if let date = info.createdAt { row(Messages.AppSchematicManagerView.createdAt.localized, LocalizedFormat.date(date, date: .abbreviated, time: .shortened)) }
                    if let date = info.modifiedAt { row(Messages.AppSchematicManagerView.modifiedAt.localized, LocalizedFormat.date(date, date: .abbreviated, time: .shortened)) }
                    row(Messages.AppSchematicManagerView.fileSize.localized, LocalizedFormat.bytes(entry.size))
                }
            } else if let error { Text(Messages.AppSchematicManagerView.previewError(error).localized).font(.callout).foregroundStyle(.orange) }
            else { ProgressView(Messages.AppSchematicManagerView.readingSchematic.localized) }
            HStack { Spacer(); Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 580)
        .task { do { info = try await manager.info(entry) } catch { self.error = error.localizedDescription } }
    }
    private func row(_ title: String, _ value: String) -> some View { GridRow { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
    private func image(_ data: Data) -> NSImage? {
        let pixels = data.count / 4, edge = Int(Double(pixels).squareRoot())
        guard edge > 0, edge * edge == pixels, data.count == pixels * 4,
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: edge, height: edge, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: edge, height: edge))
    }
}
