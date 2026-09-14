import AppKit
import Foundation
import RuriCore
import RuriLocalization

extension AppModel {
    func javaForLaunch(instance: GameInstance, manifest: VersionManifest, activityID: UUID) async throws -> JavaRuntime {
        let requirement = try GameJavaRequirement(instance: instance, manifest: manifest)
        // Re-probe at launch: Java may have been installed, moved or removed
        // since the application's last inventory refresh.
        let available = await JavaDiscovery.scan(paths: paths, extra: [instance.javaPath].compactMap { $0 })
        try Task.checkCancellation()
        if let java = try requirement.select(from: available) { return java }
        return try await requestJava(
            detail: Messages.AppJavaSetup.gameRequirement(instance.name, String(requirement.recommendedMajor), requirement.architecture).localized,
            recommendedMajor: requirement.recommendedMajor, activityID: activityID
        ) { requirement.accepts(major: $0, architecture: $1) }
    }

    func javaForInstaller(minimumMajor: Int, component: String, activityID: UUID) async throws -> JavaRuntime {
        try await requestJava(
            detail: Messages.AppJavaSetup.installerRequirement(component, String(minimumMajor)).localized,
            recommendedMajor: minimumMajor, activityID: activityID
        ) { major, architecture in
            major >= minimumMajor && (architecture == JavaRuntime.hostArchitecture || architecture == "x86_64")
        }
    }

    private func requestJava(detail: String, recommendedMajor: Int, activityID: UUID,
                             accepts: @escaping @Sendable (Int, String) -> Bool) async throws -> JavaRuntime {
        let alert = NSAlert()
        alert.messageText = Messages.AppJavaSetup.javaRequired.localized
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: Messages.AppJavaSetup.downloadAndContinue.localized)
        alert.addButton(withTitle: Messages.AppJavaSetup.chooseLocal.localized)
        alert.addButton(withTitle: Messages.Common.cancel.localized).keyEquivalent = "\u{1b}"
        progress(activityID, InstallProgress(Messages.AppJavaSetup.waitingForChoice))
        let response = try await presentJavaAlert(alert)
        switch response {
        case .alertFirstButtonReturn:
            // Resolving the catalog and downloading binaries happen only after
            // this operation's explicit download choice.
            let service = JavaInstaller(paths: paths)
            progress(activityID, InstallProgress(Messages.AppAppModelLaunching.preparingJava(String(recommendedMajor))))
            let available = try await service.available().filter { accepts($0.major, $0.architecture) }
            let runtime = available.sorted {
                if ($0.major == recommendedMajor) != ($1.major == recommendedMajor) { return $0.major == recommendedMajor }
                if $0.architecture != $1.architecture { return $0.architecture == JavaRuntime.hostArchitecture }
                return $0.major < $1.major
            }.first
            guard let runtime else { throw RuriError.message(Messages.AppAppModelLaunching.javaRuntimeUnavailable) }
            try Task.checkCancellation()
            do {
                let java = try await service.install(runtime, downloader: downloader) { [weak self] p in await self?.progress(activityID, p) }
                await scanJava()
                return java
            } catch { await scanJava(); throw error }
        case .alertSecondButtonReturn:
            let panel = NSOpenPanel()
            panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            panel.message = Messages.AppAppModelJava.javaPathPurpose.localized
            let response = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let response = await panel.begin()
                try Task.checkCancellation()
                return response
            } onCancel: {
                Task { @MainActor in panel.cancel(nil) }
            }
            guard response == .OK, let selection = panel.url else { throw CancellationError() }
            let java = try await Task.detached(priority: .userInitiated) {
                try JavaDiscovery.inspect(JavaDiscovery.executable(in: selection).path)
            }.value
            guard accepts(java.major, java.architecture) else { throw RuriError.message(Messages.CoreLaunch.javaVersionIncompatible) }
            try Task.checkCancellation()
            acceptState(try await JavaRuntimeStore.add(selection, paths: paths))
            await scanJava()
            return java
        default:
            throw CancellationError()
        }
    }

    private func presentJavaAlert(_ alert: NSAlert) async throws -> NSApplication.ModalResponse {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                response = await alert.beginSheetModal(for: window)
            } else { response = alert.runModal() }
            try Task.checkCancellation()
            return response
        } onCancel: {
            Task { @MainActor in
                if let parent = alert.window.sheetParent { parent.endSheet(alert.window, returnCode: .cancel) }
                else if NSApp.modalWindow == alert.window { NSApp.abortModal() }
            }
        }
    }
}
