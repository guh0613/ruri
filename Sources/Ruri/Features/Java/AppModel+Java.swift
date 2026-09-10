import Foundation
import RuriCore

extension AppModel {
    func scanJava() async {
        guard !scanningJava else { return }
        scanningJava = true
        let extra = state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path } + [state.settings.defaultLaunchSettings.java.path].compactMap { $0 }
        runtimes = await JavaDiscovery.scan(paths: paths, extra: extra)
        scanningJava = false
    }
}
