import SwiftUI
import RuriCore
import RuriLocalization

/// A live, bounded view of the network service, separate from durable task history.
struct LauncherTransfersView: View {
    @Environment(AppModel.self) private var model
    let search: String
    @State private var transfers: [FileTransfer] = []
    @State private var selection: String?
    private var filtered: [FileTransfer] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return transfers.filter { query.isEmpty || $0.filename.localizedStandardContains(query) || $0.host.localizedStandardContains(query) || ($0.message?.localizedStandardContains(query) ?? false) }
    }
    var body: some View {
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn(Messages.LauncherLog.filename.localized) { transfer in
                    HStack(spacing: 10) {
                        Image(systemName: transfer.state.isActive ? "arrow.down.circle" : transfer.state == .failed ? "exclamationmark.circle" : "doc")
                            .foregroundStyle(transfer.state == .failed ? Color.orange : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transfer.filename).lineLimit(1).help(transfer.filename)
                            Text(transfer.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if transfer.state.isActive, let total = transfer.totalBytes, total > 0 {
                                ProgressView(value: min(Double(transfer.receivedBytes) / Double(total), 1))
                            }
                        }.padding(.vertical, 7)
                    }
                }.width(min: 160, ideal: 330)
                TableColumn(Messages.LauncherLog.status.localized) { Text($0.state.title).font(.caption).foregroundStyle(.secondary) }.width(82)
                TableColumn(Messages.LauncherLog.transferred.localized) { transfer in
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(LocalizedFormat.bytes(transfer.receivedBytes))
                        if transfer.state == .receiving, transfer.bytesPerSecond > 0 {
                            Text(LocalizedFormat.bytes(Int64(transfer.bytesPerSecond)) + "/s").foregroundStyle(.secondary)
                        }
                    }.font(.caption).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }.width(100)
            }.tableStyle(.inset(alternatesRowBackgrounds: false)).overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? Messages.LauncherLog.noTransfers.localized : Messages.LauncherLog.noMatches.localized,
                                           systemImage: "arrow.down.circle",
                                           description: Text(search.isEmpty ? Messages.LauncherLog.transferHint.localized : Messages.LauncherLog.searchHint.localized))
                }
            }
            if let transfer = filtered.first(where: { $0.id == selection }) {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Text(transfer.filename).font(.headline).textSelection(.enabled)
                    HStack {
                        Text(transfer.host)
                        Text(Messages.AppDownloadsView.attemptNumber(Int64(transfer.attempt)).localized)
                        if transfer.resumedBytes > 0 { Text(Messages.AppDownloadsView.resumeDownload(LocalizedFormat.bytes(transfer.resumedBytes)).localized) }
                        Spacer()
                        Text(LocalizedFormat.bytes(transfer.receivedBytes) + (transfer.totalBytes.map { " / " + LocalizedFormat.bytes($0) } ?? ""))
                    }.font(.caption).foregroundStyle(.secondary)
                    if let message = transfer.message { Text(message).font(.callout).textSelection(.enabled) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text(Messages.LauncherLog.entryCount(Int64(filtered.count)).localized)
                Spacer()
                Text(Messages.LauncherLog.transferScope.localized)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 9)
        }
        .task {
            while !Task.isCancelled {
                transfers = await model.downloader.transfers()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
}
