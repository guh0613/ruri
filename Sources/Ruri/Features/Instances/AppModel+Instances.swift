import Foundation
import AppKit
import RuriCore

extension AppModel {
    func select(_ instance: GameInstance) { state.selectedInstanceID = instance.id; save() }
    func update(_ instance: GameInstance) {
        guard let index = state.instances.firstIndex(where: { $0.id == instance.id }) else { return }
        state.instances[index] = instance; save()
    }
    func updateSettings(_ draft: GameInstance, basedOn original: GameInstance) {
        guard var current = state.instances.first(where: { $0.id == draft.id }) else { return }
        func apply<Value: Equatable>(_ key: WritableKeyPath<GameInstance, Value>) {
            if draft[keyPath: key] != original[keyPath: key] { current[keyPath: key] = draft[keyPath: key] }
        }
        apply(\.name); apply(\.favorite); apply(\.iconPNG)
        var overrides = current.effectiveLaunchOverrides
        let desired = draft.effectiveLaunchOverrides, baseline = original.effectiveLaunchOverrides
        func setting<Value: Equatable>(_ key: WritableKeyPath<InstanceLaunchOverrides, Value>) {
            if desired[keyPath: key] != baseline[keyPath: key] { overrides[keyPath: key] = desired[keyPath: key] }
        }
        setting(\.memory); setting(\.java); setting(\.jvmArguments); setting(\.gameArguments); setting(\.window); setting(\.presentation); setting(\.environment)
        if overrides != current.effectiveLaunchOverrides { current.launchOverrides = overrides }
        update(current)
        Task { await scanJava() }
    }
    func reveal(_ instance: GameInstance, folder: String? = nil) {
        let base = paths.game(instance.id)
        let url = folder.map { base.appendingPathComponent($0) } ?? base
        do {
            let location = try InstanceLocationLease.acquire(paths: paths, instanceID: instance.id)
            defer { withExtendedLifetime(location) {} }
            try paths.validateInstanceLocation(instance.id)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url)
        }
        catch { self.error = error.localizedDescription }
    }
    func trash(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id), !busy else { return }
        do {
            if instance.repositoryVersionID != nil {
                save(); guard !readOnly else { return }
                acceptState(try MinecraftFolderStore.trashVersion(instance.id, paths: basePaths)); return
            }
            let lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
            defer { withExtendedLifetime(lease) {} }
            let url = paths.instance(instance.id)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            state.instances.removeAll { $0.id == instance.id }
            if state.selectedInstanceID == instance.id { state.selectedInstanceID = state.instances.first?.id }
            save()
        } catch { self.error = error.localizedDescription }
    }
}
