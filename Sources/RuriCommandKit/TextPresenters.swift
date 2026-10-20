import Foundation
import RuriCore
import RuriLocalization

/// Purpose-built text for results people read most: lists with fixed columns,
/// details grouped by meaning, and outcomes before particulars.
extension CommandTextRenderer {
    func presentation(_ value: Value) -> [String]? {
        switch path {
        case ["instance", "list"]: return instances(value)
        case ["instance", "show"]: return instance(value)
        case ["launch", "preflight"]: return preflight(value)
        case ["launch", "start"]: return value["command"] != .null ? preflight(value) : launched(value)
        default: return nil
        }
    }

    /// Indexes for short IDs, built from the whole data directory rather than
    /// the page, so a short ID shown here resolves later.
    func index(_ kind: TargetIndex.Kind, instance: UUID? = nil) -> TargetIndex? {
        request.flatMap { try? TargetCatalog(paths: CLIApplication.basePaths($0)).index(kind, instance: instance) }
    }

    func shortID(_ value: Value, in index: TargetIndex?) -> String {
        guard let text = value.string else { return "" }
        guard !layout.details, let id = UUID(uuidString: text), let index, index.entries.contains(where: { $0.id == id }) else { return text }
        return index.shortID(id)
    }

    // MARK: Instances

    private static func components(_ value: Value) -> String {
        guard case .array(let items) = value["components"], !items.isEmpty else { return LoaderKind.vanilla.title }
        return items.map { item in
            let loader = item["loader"].string ?? ""
            return (LoaderKind(rawValue: loader)?.title ?? loader) + " " + (item["version"].string ?? "")
        }.joined(separator: ", ")
    }

    private func installation(_ value: Value) -> String {
        if value["issue"].string != nil { return style.warning(Messages.CLIExperience.statusNeedsAttention.localized) }
        return value["installed"] == .bool(true) ? style.good(Messages.CLIExperience.statusInstalled.localized) : style.dim(Messages.CLIExperience.statusNotInstalled.localized)
    }

    private func instances(_ value: Value) -> [String] {
        guard case .array(let items) = value["items"] else { return [] }
        let instances = index(.instance), directories = index(.directory)
        let columns = [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) + ($0["favorite"] == .bool(true) ? " ★" : "") },
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["gameVersion"]) },
            ListColumn(header: Messages.CLIExperience.columnComponents.localized, priority: 2) { Self.components($0) },
            ListColumn(header: Messages.CLIExperience.columnStatus.localized, priority: 1) { installation($0) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { shortID($0["id"], in: instances) },
            ListColumn(header: Messages.CLIExperience.columnDirectory.localized, detailOnly: true) { directory($0["directoryID"], in: directories) },
            ListColumn(header: Messages.CLIExperience.columnPath.localized, detailOnly: true) { Self.plain($0["instanceDirectory"]) }
        ]
        var lines = page(value, items: items, columns: columns)
        // Problems stay visible however compact the table is.
        let problems = items.filter { $0["issue"].string != nil }
        if !problems.isEmpty {
            lines += [""] + layout.prose(Messages.CLIExperience.needsAttention.localized, style.warning)
            lines += layout.fields(problems.map { (Self.plain($0["name"]), Self.plain($0["issue"])) })
        }
        return lines
    }

    private func directory(_ value: Value, in index: TargetIndex?) -> String {
        guard let id = value.string.flatMap(UUID.init(uuidString:)) else { return Self.plain(value) }
        guard let index, let entry = index.entries.first(where: { $0.id == id }) else { return id.uuidString }
        return Self.reference(entry, in: index, details: layout.details)
    }

    private func instance(_ value: Value) -> [String] {
        let components = Self.components(value)
        var status = [installation(value)]
        if value["favorite"] == .bool(true) { status.append(Messages.CLIExperience.statusFavorite.localized) }
        var lines = layout.prose(Self.plain(value["name"]), style.bold)
        lines += layout.fields([
            (Messages.CLIExperience.labelID.localized, Self.plain(value["id"])),
            (Messages.CLIExperience.labelVersion.localized, Self.plain(value["gameVersion"]) + " · " + components),
            (Messages.CLIExperience.labelStatus.localized, status.joined(separator: " · "))
        ])
        if let issue = value["issue"].string { lines += layout.fields([(Messages.CLIExperience.labelIssue.localized, style.warning(Self.plain(.string(issue))))]) }
        lines += layout.section(Messages.CLIExperience.sectionLocations.localized, [
            (Messages.CLIExperience.labelDirectory.localized, directory(value["directoryID"], in: index(.directory))),
            (Messages.CLIExperience.labelRunDirectory.localized, Self.plain(value["runDirectory"])),
            (Messages.CLIExperience.labelInstanceFolder.localized, Self.plain(value["instanceDirectory"])),
            (Messages.CLIExperience.labelGameFolder.localized, Self.plain(value["gameDirectory"]))
        ])
        if layout.details {
            let icon = [value["iconGlyph"].string, value["iconTint"].string].compactMap { $0 }.joined(separator: " · ")
            lines += layout.section(Messages.CLIExperience.sectionAppearance.localized, [
                (Messages.CLIExperience.labelIcon.localized, value["hasCustomIcon"] == .bool(true) ? Messages.CLIExperience.customIcon.localized : icon)
            ])
        }
        return lines
    }

    // MARK: Launch

    private func instanceName(_ id: Value) -> String {
        guard let index = index(.instance), let uuid = id.string.flatMap(UUID.init(uuidString:)),
              let entry = index.entries.first(where: { $0.id == uuid }) else { return Self.plain(id) }
        return Self.reference(entry, in: index, details: layout.details)
    }

    private func preflight(_ value: Value) -> [String] {
        let name = instanceName(value["instanceID"])
        let headline = value["dryRun"] == .bool(true) || path.last == "start"
            ? layout.prose(Messages.CLIExperience.previewMessage(Messages.CLIExperience.launchWouldStart(name).localized).localized, style.bold)
            : layout.prose(Messages.CLIExperience.launchReady(name).localized, style.good)
        var account = Self.plain(value["accountKind"])
        if let accounts = index(.account), let id = value["accountID"].string.flatMap(UUID.init(uuidString:)), let entry = accounts.entries.first(where: { $0.id == id }) {
            account = Self.reference(entry, in: accounts, details: layout.details) + " · " + account
        }
        let environment = ((try? value["environmentNames"].decode([String].self)) ?? []).joined(separator: ", ")
        var lines = headline
        lines += layout.fields([
            (Messages.CLIExperience.labelAccount.localized, account),
            (Messages.CLIExperience.labelJava.localized, Self.atom(value["javaMajor"]) + " · " + Self.plain(value["javaPath"])),
            (Messages.CLIExperience.labelGameFolder.localized, Self.plain(value["gameDirectory"])),
            (Messages.CLIExperience.labelEnvironment.localized, environment),
            (Messages.CLIExperience.labelSignIn.localized, value["authenticationChecked"] == .bool(true) ? Messages.CLIExperience.signInChecked.localized : Messages.CLIExperience.signInAtLaunch.localized)
        ])
        if layout.details {
            if value["jvmTuning"] != .null { lines += layout.section(Messages.CLIExperience.sectionJVMTuning.localized, Self.flatten(value["jvmTuning"]).sorted { $0.key < $1.key }.map { ($0.key, Self.atom($0.value)) }) }
            lines += [style.bold(Messages.CLIExperience.sectionCommand.localized)] + layout.paragraph(Self.plain(value["command"])).map { "  " + $0 }
        }
        if let request, path.last == "preflight" || request.dryRun {
            var words = ["launch", "start"] + request.operands
            for key in ["account", "world", "server"] { if let text = request.string(key) { words += ["--" + key, text] } }
            lines.append(Messages.CLIExperience.nextAction(command(words)).localized)
        }
        return lines
    }

    private func launched(_ value: Value) -> [String] {
        let state = value["state"].string ?? ""
        let name = instanceName(value["instanceID"])
        let headline: [String]
        switch state {
        case "failed", "interrupted": headline = layout.prose(Messages.CLIExperience.launchFailed(name).localized, style.bad)
        case "succeeded", "stopped", "cancelled": headline = layout.prose(Messages.CLIExperience.launchEnded(name).localized, style.bold)
        default: headline = layout.prose(Messages.CLIExperience.launchStarted(name).localized, style.good)
        }
        let instance = value["instanceID"].string.flatMap(UUID.init(uuidString:))
        let sessions = instance.flatMap { index(.session, instance: $0) }
        var lines = headline
        lines += layout.fields([
            (Messages.CLIExperience.labelSession.localized, shortID(value["id"], in: sessions)),
            (Messages.CLIExperience.labelStatus.localized, Self.sessionState(state) + " · " + Self.progressStage("session", value)),
            (Messages.CLIExperience.labelStarted.localized, TextFormat.date(value["createdAt"])),
            (Messages.CLIExperience.labelExitCode.localized, value["gameExitCode"] == .null ? "" : Self.atom(value["gameExitCode"]))
        ])
        if let failure = value["failure"].string { lines += layout.fields([(Messages.CLIExperience.labelProblem.localized, style.bad(Self.plain(.string(failure))))]) }
        if let request, let session = value["id"].string {
            let target = request.operands.first ?? value["instanceID"].string ?? ""
            let actions = value["finished"] == .bool(true) ? [["session", "diagnose", target, session]] : [["session", "wait", target, session], ["session", "logs", target, session]]
            lines += actions.map { Messages.CLIExperience.nextAction(command($0)).localized }
        }
        return lines
    }

    static func sessionState(_ state: String) -> String {
        switch state {
        case "preparing": Messages.CLIExperience.sessionPreparing.localized
        case "running": Messages.CLIExperience.sessionRunning.localized
        case "succeeded": Messages.CLIExperience.sessionSucceeded.localized
        case "stopped": Messages.CLIExperience.sessionStopped.localized
        case "failed": Messages.CLIExperience.sessionFailed.localized
        case "cancelled": Messages.CLIExperience.sessionCancelled.localized
        case "interrupted": Messages.CLIExperience.sessionInterrupted.localized
        default: state
        }
    }
}
