import Foundation
import RuriCore
import RuriLocalization

/// What a result is for, which decides how its text reads.
enum TextPresentation: Sendable {
    /// Rows with fixed columns, paging and empty states.
    case list
    /// One resource, grouped by meaning.
    case detail
    /// The outcome first: done or a preview, then the targets and what changed.
    case change
    /// The conclusion first, then causes, evidence and what to do next.
    case diagnosis
    /// Logs and scripts, exactly as they are.
    case raw
}

extension CommandTextRenderer {
    struct Presenter {
        let presentation: TextPresentation
        let render: (CommandTextRenderer, Value) -> [String]
        init(_ presentation: TextPresentation, _ render: @escaping (CommandTextRenderer, Value) -> [String]) {
            self.presentation = presentation; self.render = render
        }
    }

    /// The presenter of every command, so no result falls back to a dump of its fields.
    static func presenter(_ path: [String]) -> Presenter? {
        switch path {
        case ["instance", "list"]: Presenter(.list) { $0.instances($1) }
        case ["instance", "show"]: Presenter(.detail) { $0.instance($1) }
        case ["instance", "selected"]: Presenter(.detail) { $0.selection($1, .instance) }
        case ["instance", "versions"]: Presenter(.list) { $0.gameVersions($1) }
        case ["instance", "create"], ["instance", "install"], ["instance", "repair"], ["instance", "rename"], ["instance", "favorite"], ["instance", "icon"],
             ["instance", "component", "set"], ["instance", "component", "restore"]: Presenter(.change) { $0.instanceChange($1) }
        case ["instance", "select"]: Presenter(.change) { $0.change($1) }
        case ["instance", "remove"]: Presenter(.change) { $0.instanceRemoval($1) }
        case ["instance", "copy"], ["instance", "move"]: Presenter(.change) { $0.instanceTransfer($1) }
        case ["instance", "export"]: Presenter(.change) { $0.change($1, [(Messages.CLIExperience.labelFile.localized, Self.plain($1["file"]))]) }
        case ["instance", "component", "list"]: Presenter(.detail) { $0.componentList($1) }
        case ["instance", "component", "versions"]: Presenter(.list) { $0.strings($1, header: Messages.CLIExperience.columnVersion.localized) }
        case ["instance", "import"], ["pack", "import"], ["pack", "install"], ["pack", "update"]: Presenter(.change) { $0.packChange($1) }
        case ["launch", "preflight"]: Presenter(.detail) { $0.preflight($1) }
        case ["launch", "start"]: Presenter(.change) { $1["command"] != .null ? $0.preflight($1) : $0.launched($1) }
        case ["session", "list"]: Presenter(.list) { $0.sessions($1) }
        case ["session", "show"], ["session", "wait"]: Presenter(.detail) { $0.session($1) }
        case ["session", "quit"], ["session", "stop"]: Presenter(.change) { $0.change($1) }
        case ["session", "logs"]: Presenter(.raw) { [$1["text"].string ?? ""] }
        case ["session", "diagnose"]: Presenter(.diagnosis) { $0.diagnosis($1) }
        case ["session", "export"]: Presenter(.change) { $0.sessionExport($1) }
        case ["directory", "list"]: Presenter(.list) { $0.directories($1) }
        case ["directory", "selected"]: Presenter(.detail) { $0.selection($1, .directory) }
        case ["directory", "scan"]: Presenter(.list) { $0.scannedVersions($1) }
        case ["directory", "add"]: Presenter(.change) { $0.directoryAddition($1) }
        case ["directory", "select"], ["directory", "refresh"], ["directory", "remove"], ["directory", "rename"], ["directory", "relocate"], ["directory", "restore"]:
            Presenter(.change) { $0.directoryChange($1) }
        case ["directory", "run", "get"]: Presenter(.detail) { $0.runDirectory($1) }
        case ["directory", "run", "set"], ["directory", "run", "relocate"]: Presenter(.change) { $0.runDirectoryChange($1) }
        case ["java", "list"]: Presenter(.list) { $0.javaRuntimes($1) }
        case ["java", "available"]: Presenter(.list) { $0.availableJava($1) }
        case ["java", "add"], ["java", "install"], ["java", "repair"]: Presenter(.change) { $0.javaChange($1) }
        case ["java", "forget"]: Presenter(.change) { $0.change($1, [(Messages.CLIExperience.labelPath.localized, Self.plain($1["path"]))]) }
        case ["java", "default"]: Presenter(.change) { $0.configurationChange($1) }
        case ["java", "references"]: Presenter(.list) { $0.strings($1, header: Messages.CLIExperience.labelUsedBy.localized) }
        case ["java", "remove"]: Presenter(.change) { $0.javaRemoval($1) }
        case ["account", "list"]: Presenter(.list) { $0.accounts($1) }
        case ["account", "selected"]: Presenter(.detail) { $0.selection($1, .account) }
        case ["account", "show"]: Presenter(.detail) { $0.account($1) }
        case ["account", "add-offline"], ["account", "refresh"], ["account", "login", "complete"]: Presenter(.change) { $0.accountChange($1) }
        case ["account", "select"], ["account", "remove"], ["account", "logout"], ["account", "service-key", "set"], ["account", "service-key", "remove"]:
            Presenter(.change) { $0.change($1) }
        case ["account", "login", "start"]: Presenter(.change) { $0.loginStart($1) }
        case ["account", "login", "cancel"]: Presenter(.change) { $0.change($1, [(Messages.CLIExperience.labelSignInFlow.localized, Self.plain($1["flowID"]))]) }
        case ["account", "service-key", "status"]: Presenter(.detail) { $0.serviceKey($1) }
        case ["server", "list"]: Presenter(.list) { $0.servers($1) }
        case ["server", "add"]: Presenter(.change) { $1["items"] != .null ? $0.serverListChange($1) : $0.serverPreference($1) }
        case ["server", "edit"], ["server", "remove"], ["server", "move"]: Presenter(.change) { $0.serverListChange($1) }
        case ["server", "favorite"], ["server", "preferences"]: Presenter(.change) { $0.serverPreference($1) }
        case ["server", "query"]: Presenter(.detail) { $0.serverStatus($1) }
        case ["catalog", "search"], ["datapack", "search"]: Presenter(.list) { $0.projects($1) }
        case ["catalog", "show"]: Presenter(.detail) { $0.project($1) }
        case ["catalog", "versions"], ["datapack", "versions"]: Presenter(.list) { $0.projectVersions($1) }
        case ["catalog", "categories"]: Presenter(.list) { $0.categories($1) }
        case ["content", "list"]: Presenter(.list) { $0.contentFiles($1) }
        case ["content", "import"]: Presenter(.change) { $0.contentImport($1) }
        case ["content", "install"]: Presenter(.change) { $0.contentInstall($1) }
        case ["content", "enable"], ["content", "disable"], ["content", "remove"]: Presenter(.change) { $0.contentChange($1) }
        case ["content", "update-check"], ["content", "update"]: Presenter(.change) { $0.contentUpdates($1) }
        case ["pack", "show"]: Presenter(.detail) { $0.pack($1) }
        case ["pack", "update-check"]: Presenter(.list) { $0.packReleases($1) }
        case ["pack", "rollback"]: Presenter(.change) { $0.packRollback($1) }
        case ["download", "fetch"]: Presenter(.change) { $0.download($1) }
        case ["world", "list"]: Presenter(.list) { $0.worlds($1) }
        case ["world", "show"]: Presenter(.detail) { $0.world($1) }
        case ["world", "import"], ["world", "export"], ["world", "remove"]: Presenter(.change) { $0.worldChange($1) }
        case ["world", "backup", "create"], ["world", "backup", "restore"], ["world", "backup", "remove"]: Presenter(.change) { $0.backupChange($1) }
        case ["world", "backup", "list"]: Presenter(.list) { $0.backups($1) }
        case ["datapack", "list"]: Presenter(.list) { $0.dataPacks($1) }
        case ["datapack", "order", "get"]: Presenter(.detail) { $0.dataPackOrder($1) }
        case ["datapack", "order", "set"]: Presenter(.change) { $0.change($1) + $0.dataPackOrder($1) }
        case ["datapack", "import"], ["datapack", "enable"], ["datapack", "disable"], ["datapack", "remove"]: Presenter(.change) { $0.dataPackChange($1) }
        case ["datapack", "install"]: Presenter(.change) { $0.dataPackInstall($1) }
        case ["schematic", "list"]: Presenter(.list) { $0.schematics($1) }
        case ["schematic", "info"]: Presenter(.detail) { $0.schematic($1) }
        case ["schematic", "import"], ["schematic", "mkdir"], ["schematic", "export"], ["schematic", "remove"]: Presenter(.change) { $0.schematicChange($1) }
        case ["config", "get"]: Presenter(.detail) { $0.configuration($1) }
        case ["config", "set"], ["config", "apply"], ["config", "reset"], ["config", "inherit"]: Presenter(.change) { $0.configurationChange($1) }
        case ["config", "fields"]: Presenter(.list) { $0.configurationFields($1) }
        case ["recovery", "list"]: Presenter(.list) { $0.recoveryItems($1) }
        case ["recovery", "apply"]: Presenter(.change) { $0.recovery($1) }
        case ["doctor"]: Presenter(.diagnosis) { $0.doctor($1) }
        case ["app", "info"]: Presenter(.detail) { $0.appInfo($1) }
        case ["app", "language", "get"]: Presenter(.detail) { $0.language($1) }
        case ["app", "language", "set"]: Presenter(.change) { $0.change($1, [(Messages.CLIExperience.labelLanguage.localized, Self.plain($1["language"]))]) }
        case ["cli", "status"]: Presenter(.detail) { $0.cliStatus($1) }
        case ["cli", "install"], ["cli", "uninstall"]: Presenter(.change) { $0.cliChange($1) }
        case ["cache", "status"], ["cache", "clean"]: Presenter(.change) { $0.cache($1) }
        case ["schema"]: Presenter(.detail) { $0.schema($1) }
        case ["completions"]: Presenter(.raw) { [$1["script"].string ?? ""] }
        default: nil
        }
    }

    // MARK: Shared

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

    /// A resource by name and short ID, or its ID when it is not known here.
    func reference(_ id: Value, in index: TargetIndex?) -> String {
        guard let uuid = id.string.flatMap(UUID.init(uuidString:)), let index, let entry = index.entries.first(where: { $0.id == uuid }) else { return Self.plain(id) }
        return Self.reference(entry, in: index, details: layout.details)
    }

    func known(_ id: Value, in index: TargetIndex?) -> Bool {
        index?.entries.contains { $0.id.uuidString == id.string } == true
    }

    /// The first sentence of what the command does.
    private var action: String {
        let summary = request?.spec.summary ?? ""
        for separator in [". ", "\u{3002}"] {
            if let range = summary.range(of: separator) { return String(summary[..<range.lowerBound]) + separator.trimmingCharacters(in: .whitespaces) }
        }
        return summary
    }

    /// Done or a preview, with what the command does.
    func outcome(_ value: Value) -> [String] {
        value["dryRun"] == .bool(true)
            ? layout.prose(Messages.CLIExperience.previewMessage(action).localized, style.bold)
            : layout.prose(Messages.CLIExperience.completedMessage(action).localized, style.good)
    }

    /// The outcome, the targets as they were before the command ran, the rows
    /// that matter for this command and anything it kept or warned about.
    func change(_ value: Value, _ rows: [(String, String)] = []) -> [String] {
        outcome(value) + layout.fields(targets() + rows) + notices(value)
    }

    /// Warnings and preserved files, which a short result never hides.
    func notices(_ value: Value) -> [String] {
        var lines: [String] = []
        if let warning = value["warning"].string { lines += layout.prose(Messages.CLIExperience.warning(Self.plain(.string(warning))).localized, style.warning) }
        let preserved = ([value["preservedCopy"], value["preservedFiles"]] + value["preservedFiles"].elements).compactMap(\.string)
        if !preserved.isEmpty { lines += layout.prose(Messages.CLIExperience.preservedFiles.localized, style.bold) + preserved.map { "  " + $0 } }
        return lines
    }

    /// The selected instance or directory, or the active account.
    func selection(_ value: Value, _ kind: TargetIndex.Kind) -> [String] {
        let name = reference(value["id"], in: index(kind))
        switch kind {
        case .account: return layout.prose(value["id"] == .null ? Messages.CLIExperience.noActiveAccount.localized : Messages.CLIExperience.activeAccount(name).localized)
        case .directory: return layout.prose(Messages.CLIExperience.selectedDirectory(name).localized)
        default: return layout.prose(value["id"] == .null ? Messages.CLIExperience.noSelectedInstance.localized : Messages.CLIExperience.selectedInstance(name).localized)
        }
    }

    /// A one-column list of plain values.
    func strings(_ value: Value, header: String) -> [String] {
        page(value, items: value["items"].elements, columns: [ListColumn(header: header) { Self.plain($0) }])
    }

    static func yes(_ flag: Bool) -> String { flag ? Messages.CLIExperience.yes.localized : Messages.CLIExperience.no.localized }

    // MARK: Instances

    static func components(_ value: Value) -> String {
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

    private func instanceStatus(_ value: Value) -> String {
        var status = [installation(value)]
        if value["favorite"] == .bool(true) { status.append(Messages.CLIExperience.statusFavorite.localized) }
        return status.joined(separator: " · ")
    }

    func instances(_ value: Value) -> [String] {
        let items = value["items"].elements, instances = index(.instance), directories = index(.directory)
        let columns = [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) + ($0["favorite"] == .bool(true) ? " ★" : "") },
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["gameVersion"]) },
            ListColumn(header: Messages.CLIExperience.columnComponents.localized, priority: 2) { Self.components($0) },
            ListColumn(header: Messages.CLIExperience.columnStatus.localized, priority: 1) { installation($0) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { shortID($0["id"], in: instances) },
            ListColumn(header: Messages.CLIExperience.columnDirectory.localized, detailOnly: true) { reference($0["directoryID"], in: directories) },
            ListColumn(header: Messages.CLIExperience.columnPath.localized, detailOnly: true) { Self.plain($0["instanceDirectory"]) }
        ]
        // Problems stay visible however compact the table is.
        return page(value, items: items, columns: columns, problems: items.compactMap { item in item["issue"].string.map { (Self.plain(item["name"]), Self.plain(.string($0))) } })
    }

    func instance(_ value: Value) -> [String] {
        var lines = layout.prose(Self.plain(value["name"]), style.bold)
        lines += layout.fields([
            (Messages.CLIExperience.labelID.localized, Self.plain(value["id"])),
            (Messages.CLIExperience.labelVersion.localized, Self.plain(value["gameVersion"]) + " · " + Self.components(value)),
            (Messages.CLIExperience.labelStatus.localized, instanceStatus(value))
        ])
        if let issue = value["issue"].string { lines += layout.fields([(Messages.CLIExperience.labelIssue.localized, style.warning(Self.plain(.string(issue))))]) }
        lines += layout.section(Messages.CLIExperience.sectionLocations.localized, [
            (Messages.CLIExperience.labelDirectory.localized, reference(value["directoryID"], in: index(.directory))),
            (Messages.CLIExperience.labelRunDirectory.localized, Self.runMode(value["runDirectory"])),
            (Messages.CLIExperience.labelInstanceFolder.localized, Self.plain(value["instanceDirectory"])),
            (Messages.CLIExperience.labelGameFolder.localized, Self.plain(value["gameDirectory"]))
        ])
        if layout.details { lines += layout.section(Messages.CLIExperience.sectionAppearance.localized, [(Messages.CLIExperience.labelIcon.localized, Self.icon(value))]) }
        return lines
    }

    static func icon(_ value: Value) -> String {
        value["hasCustomIcon"] == .bool(true) ? Messages.CLIExperience.customIcon.localized : [value["iconGlyph"].string, value["iconTint"].string].compactMap { $0 }.joined(separator: " · ")
    }

    static func runMode(_ value: Value) -> String { GameRunDirectory(rawValue: value.string ?? "")?.title ?? plain(value) }

    func gameVersions(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["id"]) },
            ListColumn(header: Messages.CLIExperience.labelType.localized) { item in
                switch item["type"].string {
                case "release"?: Messages.CLIExperience.versionRelease.localized
                case "snapshot"?: Messages.CLIExperience.versionSnapshot.localized
                default: Self.plain(item["type"])
                }
            }
        ])
    }

    /// Creation, installation and edits: the instance as it is now.
    func instanceChange(_ value: Value) -> [String] {
        let instance = value["instance"] == .null ? value : value["instance"], instances = index(.instance)
        var rows: [(String, String)] = []
        if path.last == "create" {
            rows.append((Messages.CLIExperience.labelInstance.localized, known(instance["id"], in: instances) ? reference(instance["id"], in: instances) : Self.plain(instance["name"])))
        } else if path.last == "rename" {
            rows.append((Messages.CLIExperience.labelName.localized, Self.plain(instance["name"])))
        }
        // A component preview lists the selection alone.
        if instance["gameVersion"] == .null { rows.append((Messages.CLIExperience.labelComponents.localized, Self.components(instance))) }
        else {
            rows.append((Messages.CLIExperience.labelVersion.localized, Self.plain(instance["gameVersion"]) + " · " + Self.components(instance)))
            rows.append((Messages.CLIExperience.labelStatus.localized, instanceStatus(instance)))
        }
        if path.last == "icon" { rows.append((Messages.CLIExperience.labelIcon.localized, Self.icon(instance))) }
        if let issue = instance["issue"].string { rows.append((Messages.CLIExperience.labelIssue.localized, style.warning(Self.plain(.string(issue))))) }
        return change(value, rows)
    }

    func instanceRemoval(_ value: Value) -> [String] {
        var lines = change(value, [(Messages.CLIExperience.labelInstanceFolder.localized, Self.plain(value["instanceDirectory"]))])
        if value["retainsExternalGameDirectory"] == .bool(true) { lines += layout.prose(Messages.CLIExperience.gameFolderKept.localized, style.dim) }
        return lines
    }

    /// Copies and moves: where from, where to and how much.
    func instanceTransfer(_ value: Value) -> [String] {
        var rows: [(String, String)] = []
        if path.last == "copy" {
            rows.append(value["dryRun"] == .bool(true)
                ? (Messages.CLIExperience.labelName.localized, request?.string("name") ?? "")
                : (Messages.CLIExperience.labelNewInstance.localized, reference(value["instanceID"], in: index(.instance))))
        }
        rows += [(Messages.CLIExperience.labelFrom.localized, Self.plain(value["source"])), (Messages.CLIExperience.labelTo.localized, Self.plain(value["destination"])),
                 (Messages.CLIExperience.labelContents.localized, TextFormat.contents(files: value["files"], bytes: value["bytes"])),
                 (Messages.CLIExperience.labelGameFolderKept.localized, Self.plain(value["retainedGameDirectory"]))]
        return change(value, rows)
    }

    func componentList(_ value: Value) -> [String] {
        var rows = [(Messages.CLIExperience.labelComponents.localized, Self.components(value)),
                    (Messages.CLIExperience.labelBackup.localized, value["backup"].string ?? Messages.CLIExperience.noBackup.localized)]
        if let reason = value["unavailableReason"].string { rows.append((Messages.CLIExperience.labelCannotChange.localized, style.warning(Self.plain(.string(reason))))) }
        return layout.fields(targets() + rows)
    }

    // MARK: Launch

    func preflight(_ value: Value) -> [String] {
        let name = reference(value["instanceID"], in: index(.instance))
        let headline = value["dryRun"] == .bool(true) || path.last == "start"
            ? layout.prose(Messages.CLIExperience.previewMessage(Messages.CLIExperience.launchWouldStart(name).localized).localized, style.bold)
            : layout.prose(Messages.CLIExperience.launchReady(name).localized, style.good)
        var account = Self.plain(value["accountKind"])
        if let accounts = index(.account), known(value["accountID"], in: accounts) { account = reference(value["accountID"], in: accounts) + " · " + account }
        let environment = value["environmentNames"].strings.joined(separator: ", ")
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
            lines += [style.bold(Messages.CLIExperience.sectionCommand.localized)] + layout.paragraph(Self.plain(value["command"]), indent: 2)
        }
        if let request, path.last == "preflight" || request.dryRun {
            var words = ["launch", "start"] + request.operands
            for key in ["account", "world", "server"] { if let text = request.string(key) { words += ["--" + key, text] } }
            lines.append(Messages.CLIExperience.nextAction(command(words)).localized)
        }
        return lines
    }

    func launched(_ value: Value) -> [String] {
        let name = reference(value["instanceID"], in: index(.instance))
        let headline: [String]
        switch value["state"].string {
        case "failed", "interrupted": headline = layout.prose(Messages.CLIExperience.launchFailed(name).localized, style.bad)
        case "succeeded", "stopped", "cancelled": headline = layout.prose(Messages.CLIExperience.launchEnded(name).localized, style.bold)
        default: headline = layout.prose(Messages.CLIExperience.launchStarted(name).localized, style.good)
        }
        return headline + layout.fields(sessionRows(value)) + sessionActions(value)
    }

    // MARK: Sessions

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

    private func sessionStatus(_ value: Value) -> String {
        let state = value["state"].string ?? "", text = Self.sessionState(state)
        switch state {
        case "failed", "interrupted": return style.bad(text)
        case "preparing", "running": return style.good(text)
        default: return text
        }
    }

    private func sessionIndex(_ value: Value) -> TargetIndex? {
        value["instanceID"].string.flatMap(UUID.init(uuidString:)).flatMap { index(.session, instance: $0) }
    }

    func sessions(_ value: Value) -> [String] {
        let items = value["items"].elements
        // Session IDs are short within their instance.
        var indexes: [String: TargetIndex] = [:]
        for instance in Set(items.compactMap { $0["instanceID"].string }) { indexes[instance] = sessionIndex(.object(["instanceID": .string(instance)])) }
        func short(_ item: Value) -> String { shortID(item["id"], in: item["instanceID"].string.flatMap { indexes[$0] }) }
        let columns = [
            ListColumn(header: Messages.CLIExperience.labelInstance.localized) { Self.plain($0["instanceName"]) },
            ListColumn(header: Messages.CLIExperience.columnStatus.localized) { sessionStatus($0) },
            ListColumn(header: Messages.CLIExperience.labelStarted.localized, priority: 1) { TextFormat.date($0["createdAt"]) },
            ListColumn(header: Messages.CLIExperience.labelPlayed.localized, priority: 2) { item in item["playedSeconds"].int.map { $0 > 0 ? TextFormat.duration(Double($0)) : "" } ?? "" },
            ListColumn(header: Messages.CLIExperience.labelExitCode.localized, priority: 3) { $0["gameExitCode"] == .null ? "" : Self.atom($0["gameExitCode"]) },
            ListColumn(header: Messages.CLIExperience.labelSession.localized) { short($0) }
        ]
        return page(value, items: items, columns: columns, problems: items.compactMap { item in item["failure"].string.map { (short(item), Self.plain(.string($0))) } })
    }

    private func sessionRows(_ value: Value) -> [(String, String)] {
        [(Messages.CLIExperience.labelSession.localized, shortID(value["id"], in: sessionIndex(value))),
         (Messages.CLIExperience.labelStatus.localized, sessionStatus(value) + " · " + Self.progressStage("session", value)),
         (Messages.CLIExperience.labelStarted.localized, TextFormat.date(value["createdAt"])),
         (Messages.CLIExperience.labelPlayed.localized, value["playedSeconds"].int.map { $0 > 0 ? TextFormat.duration(Double($0)) : "" } ?? ""),
         (Messages.CLIExperience.labelExitCode.localized, value["gameExitCode"] == .null ? "" : Self.atom(value["gameExitCode"])),
         (Messages.CLIExperience.labelProblem.localized, value["failure"].string.map { style.bad(Self.plain(.string($0))) } ?? "")]
    }

    /// Follow a running game, or find out why it failed.
    private func sessionActions(_ value: Value) -> [String] {
        guard let request, let session = value["id"].string else { return [] }
        let target = request.operands.first ?? value["instanceID"].string ?? ""
        let actions: [[String]]
        if value["finished"] != .bool(true) { actions = [["session", "wait", target, session], ["session", "logs", target, session]] }
        else if ["failed", "interrupted"].contains(value["state"].string ?? "") || path.first == "launch" { actions = [["session", "diagnose", target, session]] }
        else { actions = [] }
        return actions.map { Messages.CLIExperience.nextAction(command($0)).localized }
    }

    func session(_ value: Value) -> [String] {
        let instances = index(.instance)
        let title = known(value["instanceID"], in: instances) ? reference(value["instanceID"], in: instances) : Self.plain(value["instanceName"])
        var lines = layout.prose(title, style.bold) + layout.fields(sessionRows(value))
        if layout.details {
            lines += layout.section(Messages.CLIExperience.sectionActivity.localized, value["segments"].elements.map { segment in
                (Self.plain(segment["name"]), [Self.plain(segment["kind"]), segment["seconds"].int.map { TextFormat.duration(Double($0)) } ?? ""].joined(separator: " · "))
            })
        }
        return lines + sessionActions(value)
    }

    func sessionExport(_ value: Value) -> [String] {
        let files = value["files"].elements
        let bytes = files.compactMap { $0["bytes"].int }.reduce(0, +), redacted = files.filter { $0["redacted"] == .bool(true) }.count
        var lines = change(value, [(Messages.CLIExperience.labelFile.localized, Self.plain(value["file"])),
                                   (Messages.CLIExperience.labelContents.localized, TextFormat.contents(files: .integer(files.count), bytes: .integer(bytes)))])
        if redacted > 0 { lines += layout.prose(Messages.CLIExperience.redactedFiles(Int64(redacted)).localized, style.dim) }
        if layout.details { lines += layout.table([ListColumn(header: Messages.CLIExperience.columnPath.localized) { Self.plain($0["path"]) },
                                                   ListColumn(header: Messages.CLIExperience.labelSize.localized) { TextFormat.bytes($0["bytes"]) }], files).lines }
        return lines
    }

    /// The summary, each finding with its cause, steps and evidence, what the
    /// records could not show, and commands for the suggested actions.
    func diagnosis(_ value: Value) -> [String] {
        let findings = value["findings"].elements
        var lines = layout.prose(Self.plain(value["summary"]), findings.isEmpty ? style.bold : style.warning)
        for (number, finding) in findings.enumerated() {
            let confidence = finding["confidence"].string == "reported" ? Messages.CoreGameDiagnosis.logExplicitReport.localized : Messages.CoreGameDiagnosis.cluesNeedingVerification.localized
            lines += [""] + layout.prose("\(number + 1). " + Self.plain(finding["title"]) + " · " + confidence, style.bold)
            lines += layout.paragraph(Self.plain(finding["explanation"]), indent: 3)
            lines += layout.bullets(finding["steps"].strings.map { Self.plain(.string($0)) }, indent: 3)
            let evidence = finding["evidence"].elements, shown = layout.details ? evidence : Array(evidence.prefix(3))
            if !shown.isEmpty {
                lines.append("   " + style.bold(Messages.CLIExperience.labelEvidence.localized))
                for item in shown { lines += layout.paragraph(Self.plain(item["documentID"]) + ":" + Self.atom(item["line"]) + "  " + Self.plain(item["excerpt"]), indent: 5) }
                if evidence.count > shown.count { lines += layout.prose(Messages.CLIExperience.moreEvidence(Int64(evidence.count - shown.count)).localized, style.dim).map { "     " + $0 } }
            }
        }
        for (title, items) in [(Messages.CLIExperience.sectionFacts.localized, value["facts"].strings), (Messages.CLIExperience.sectionLimitations.localized, value["limitations"].strings)] where !items.isEmpty {
            lines += ["", style.bold(title)] + layout.bullets(items.map { Self.plain(.string($0)) })
        }
        let actions = diagnosisActions(findings)
        if !actions.isEmpty { lines.append("") }
        return lines + actions.map { Messages.CLIExperience.nextAction(command($0)).localized }
    }

    /// The commands that carry out the actions a diagnosis suggests.
    private func diagnosisActions(_ findings: [Value]) -> [[String]] {
        guard let request, request.operands.count >= 2 else { return [] }
        let instance = request.operands[0], session = request.operands[1]
        var commands: [[String]] = []
        for action in findings.flatMap({ $0["actions"].strings }) {
            let command: [String]
            switch action {
            case "settings": command = ["config", "get", "--scope", "instance:" + instance]
            case "mods": command = ["content", "list", instance]
            case "accounts": command = ["account", "list"]
            case "repair": command = ["instance", "repair", instance]
            case "files": command = ["directory", "run", "get", instance]
            case "collect": command = ["session", "export", instance, session, "ruri-session-" + shortID(.string(session), in: index(.session, instance: UUID(uuidString: instance))) + ".zip"]
            default: continue
            }
            if !commands.contains(command) { commands.append(command) }
        }
        return commands
    }
}
