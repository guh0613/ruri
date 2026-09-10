import SwiftUI
import AppKit
import RuriCore

struct JavaView: View {
    @Environment(AppModel.self) private var model
    @State private var available: [RemoteJava] = []
    @State private var javaError: String?
    @State private var loadingRemote = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: "为游戏选对 Java", subtitle: "自动识别版本与架构，让每个实例使用合适的运行时。")
                    Spacer(); Button("重新检测", systemImage: "arrow.clockwise") { Task { await model.scanJava() } }.disabled(model.scanningJava)
                }
                if model.scanningJava { ProgressView("正在检测本机 Java…") }
                if model.runtimes.isEmpty && !model.scanningJava { EmptyPanel(symbol: "cup.and.saucer", title: "没有找到 Java", detail: "安装与游戏版本匹配的 Java，然后重新检测。") }
                ForEach(model.runtimes) { java in
                    Surface {
                        HStack(spacing: 18) {
                            Text("\(java.major)").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent).frame(width: 54, height: 54).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(java.label).font(.headline); if java.isNative { TagPill(text: "原生") } }
                                Text(java.version).font(.caption).foregroundStyle(.secondary)
                                Text(java.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(java.path)
                            }
                            Spacer(); Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: java.path)]) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("在 Finder 中显示")
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("下载官方游戏运行时").font(.headline)
                        Text("Minecraft 的 Java 要求以版本清单为准。旧版游戏可能需要 Intel Java 和 Rosetta；较新版本优先使用 Apple Silicon 原生运行时。").font(.callout).foregroundStyle(.secondary)
                        if loadingRemote { ProgressView("获取 Mojang 运行时列表…").controlSize(.small) }
                        if let javaError { Text(javaError).font(.caption).foregroundStyle(.orange) }
                        ForEach(available) { runtime in
                            let installed = model.runtimes.contains { $0.path.hasPrefix(model.paths.runtimes.appendingPathComponent(runtime.id).path + "/") }
                            let resumable = FileManager.default.fileExists(atPath: model.paths.runtimes.appendingPathComponent(".partial-\(runtime.id)").path)
                            HStack {
                                Text(runtime.label).font(.callout)
                                Spacer()
                                Button(installed ? "已安装" : resumable ? "继续安装" : "安装") {
                                    model.perform("安装 Java \(runtime.major)") { id in
                                        _ = try await JavaInstaller(paths: model.paths).install(runtime, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                                        await model.scanJava()
                                    }
                                    model.page = .downloads
                                }.disabled(model.busy || installed)
                            }
                        }
                        HStack { Link("Azul Zulu 下载", destination: URL(string: "https://www.azul.com/downloads/?package=jdk#zulu")!); Link("Eclipse Temurin 下载", destination: URL(string: "https://adoptium.net/temurin/releases/?os=mac")!) }.font(.callout)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }.task {
            loadingRemote = true
            do { available = try await JavaInstaller(paths: model.paths).available() } catch { javaError = error.localizedDescription }
            loadingRemote = false
        }
    }
}
