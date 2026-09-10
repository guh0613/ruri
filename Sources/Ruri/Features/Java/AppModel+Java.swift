import Foundation
import AppKit
import RuriCore

extension AppModel {
    func scanJava() async {
        guard !scanningJava else { javaScanAgain = true; return }
        scanningJava = true
        repeat {
            javaScanAgain = false
            let extra = state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path } + [state.settings.defaultLaunchSettings.java.path].compactMap { $0 }
            javaEntries = await JavaDiscovery.inventory(paths: paths, extra: extra)
            runtimes = javaEntries.compactMap(\.runtime)
        } while javaScanAgain
        scanningJava = false
    }
    func chooseJava(replacing path: String? = nil) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = path == nil ? "选择 java 可执行文件、JDK 包或 Java Home 文件夹。" : "选择新的 Java 路径，原来指定这一路径的实例和默认设置会随之更新。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save()
        perform(path == nil ? "添加本机 Java" : "重新选择 Java") { [self] _ in
            let saved = try await JavaRuntimeStore.add(url, replacing: path, paths: paths)
            acceptState(saved); await scanJava(); notice = "Java 已添加，可在启动设置中选择"
        }
    }
    func forgetJava(_ path: String) {
        do { save(); acceptState(try JavaRuntimeStore.forget(path, paths: paths)); Task { await scanJava() } }
        catch { self.error = error.localizedDescription }
    }
    func defaultJava(_ path: String) {
        do { save(); acceptState(try JavaRuntimeStore.useByDefault(path, paths: paths)); notice = "已更新默认 Java，下一次启动生效" }
        catch { self.error = error.localizedDescription }
    }
    func installJava(_ runtime: RemoteJava, repairing: Bool = false) {
        perform("\(repairing ? "修复" : "安装") \(runtime.label)") { [self] id in
            do {
                _ = try await JavaInstaller(paths: paths).install(runtime, downloader: downloader, repairing: repairing) { [weak self] p in await self?.progress(id, p) }
                await scanJava(); notice = repairing ? "Java 已修复" : "Java 已安装"
            } catch { await scanJava(); throw error }
        }
    }
    func removeJava(_ id: String, resetReferences: Bool, partial: Bool) {
        save()
        perform(partial ? "清理 Java 未完成下载" : "移除 Java") { [self] _ in
            let paths = paths
            let result = try await Task.detached(priority: .userInitiated) { try JavaRuntimeStore.trash(id, paths: paths, resetReferences: resetReferences, partial: partial) }.value
            acceptState(result.state); await scanJava(); notice = "Java 文件已移到废纸篓"; noticeFileURL = result.trashedURL
        }
    }
}
