import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var transfers: [FileTransfer] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.activities.isEmpty { EmptyPanel(symbol: "arrow.down.circle", title: "没有下载任务", detail: "安装游戏或下载内容时，可以在这里查看进度。文件会自动校验，重试时继续下载未完成的部分。") }
                ForEach(model.activities) { activity in
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: activity.status == .completed ? "checkmark.circle.fill" : activity.status == .failed ? "exclamationmark.circle" : "arrow.down.circle").foregroundStyle(activity.status == .failed ? Color.orange : Theme.accent)
                                Text(activity.title).font(.headline); Spacer()
                                if activity.status == .running { Button("取消") { model.operation?.cancel() } }
                                else { Text(activity.status == .completed ? "已完成" : activity.status == .cancelled ? "已取消" : "失败").font(.caption).foregroundStyle(.secondary) }
                            }
                            if activity.status == .running {
                                if activity.progress.total > 0 { ProgressView(value: activity.progress.fraction) }
                                else { ProgressView().controlSize(.small) }
                                HStack { Text(activity.progress.stage); Spacer(); if activity.progress.total > 0 { Text("\(activity.progress.completed) / \(activity.progress.total)").monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = activity.error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                }
                if !transfers.isEmpty {
                    Text("最近的文件传输").font(.headline)
                    Surface {
                        VStack(spacing: 15) {
                            ForEach(transfers) { transfer in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(transfer.filename).font(.callout.weight(.medium)).lineLimit(1)
                                        Spacer()
                                        Text(transfer.state.title).font(.caption).foregroundStyle(transfer.state == .failed ? .orange : .secondary)
                                    }
                                    if transfer.state.isActive, let total = transfer.totalBytes, total > 0 { ProgressView(value: min(Double(transfer.receivedBytes) / Double(total), 1)) }
                                    ViewThatFits(in: .horizontal) {
                                        HStack { sourceInfo(transfer).fixedSize(); Spacer(minLength: 12); byteInfo(transfer).fixedSize() }
                                        VStack(alignment: .leading, spacing: 4) { sourceInfo(transfer); byteInfo(transfer) }
                                    }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    if let message = transfer.message, transfer.state != .cancelled { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                                if transfer.id != transfers.last?.id { Divider() }
                            }
                        }
                    }
                }
            }.padding(28)
        }
        .task {
            while !Task.isCancelled {
                transfers = await model.installer.downloader.transfers()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func sourceInfo(_ transfer: FileTransfer) -> some View {
        HStack {
            Text(transfer.host).lineLimit(1).truncationMode(.middle)
            if transfer.attempt > 1 { Text("第 \(transfer.attempt) 次尝试") }
            if transfer.resumedBytes > 0 { Text("续传 \(bytes(transfer.resumedBytes))") }
        }
    }
    private func byteInfo(_ transfer: FileTransfer) -> some View {
        HStack {
            Text(bytes(transfer.receivedBytes) + (transfer.totalBytes.map { " / " + bytes($0) } ?? ""))
            if transfer.state == .receiving, transfer.bytesPerSecond > 0 { Text(bytes(Int64(transfer.bytesPerSecond)) + "/s") }
        }
    }
}
