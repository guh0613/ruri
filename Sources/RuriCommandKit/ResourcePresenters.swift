import Foundation
import RuriCore
import RuriLocalization

/// Directories, Java runtimes, accounts and servers.
extension CommandTextRenderer {
    // MARK: Directories

    static func directoryLayout(_ value: Value) -> String {
        value.string == "minecraft" ? Messages.CLIExperience.layoutMinecraft.localized : Messages.CLIExperience.layoutManaged.localized
    }

    private func directoryStatus(_ value: Value) -> String {
        if value["detached"] == .bool(true) { return style.dim(Messages.CLIExperience.statusRemovedFromList.localized) }
        if value["available"] == .bool(false) { return style.warning(Messages.CLIExperience.statusUnavailable.localized) }
        return Messages.CLIExperience.statusAvailable.localized
    }

    func directories(_ value: Value) -> [String] {
        let directories = index(.directory)
        return page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) },
            ListColumn(header: Messages.CLIExperience.labelKind.localized, priority: 2) { Self.directoryLayout($0["layout"]) },
            ListColumn(header: Messages.CLIExperience.columnStatus.localized, priority: 1) { directoryStatus($0) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { shortID($0["id"], in: directories) },
            ListColumn(header: Messages.CLIExperience.columnPath.localized, priority: 3) { Self.plain($0["path"]) }
        ])
    }

    /// Versions found in a Minecraft folder, with anything that stops them from running.
    func scannedVersions(_ value: Value) -> [String] {
        let items = value["items"].elements
        return page(value, items: items, columns: [
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["id"]) },
            ListColumn(header: Messages.CLIExperience.labelGameVersion.localized, priority: 1) { Self.plain($0["gameVersion"]) },
            ListColumn(header: Messages.CLIExperience.columnComponents.localized, priority: 2) { item in
                item["components"].elements.map { Self.plain($0["name"]) + " " + Self.plain($0["version"]) }.joined(separator: ", ")
            }
        ], problems: items.flatMap { item in ([item["issue"].string].compactMap { $0 } + item["warnings"].strings).map { (Self.plain(item["id"]), Self.plain(.string($0))) } })
    }

    func directoryAddition(_ value: Value) -> [String] {
        let entry = value["dryRun"] == .bool(true) ? value : value["directories"].elements.last { $0["name"].string == request?.string("name") } ?? .null
        let name = known(entry["id"], in: index(.directory)) ? reference(entry["id"], in: index(.directory)) : Self.plain(entry["name"])
        return change(value, [(Messages.CLIExperience.labelDirectory.localized, name), (Messages.CLIExperience.labelKind.localized, entry == .null ? "" : Self.directoryLayout(entry["layout"])),
                              (Messages.CLIExperience.labelPath.localized, Self.plain(entry["path"]))])
    }

    /// The directory as it is now; a preview names the instances it affects.
    func directoryChange(_ value: Value) -> [String] {
        if value["dryRun"] == .bool(true) {
            let instances = index(.instance), affected = value["instances"].elements.map { reference($0, in: instances) }
            return change(value, path.last == "select" ? [] : [(Messages.CLIExperience.labelInstances.localized, affected.joined(separator: ", "))])
        }
        guard let entry = value["directories"].elements.first(where: { $0["id"] == value["id"] }) else { return change(value) }
        var rows: [(String, String)] = []
        if path.last == "rename" { rows.append((Messages.CLIExperience.labelName.localized, Self.plain(entry["name"]))) }
        if path.last != "select" { rows += [(Messages.CLIExperience.labelPath.localized, Self.plain(entry["path"])), (Messages.CLIExperience.labelStatus.localized, directoryStatus(entry))] }
        return change(value, rows)
    }

    func runDirectory(_ value: Value) -> [String] {
        layout.fields(targets() + [(Messages.CLIExperience.labelRunDirectory.localized, Self.runMode(value["mode"])),
                                   (Messages.CLIExperience.labelGameFolder.localized, Self.plain(value["path"])),
                                   (Messages.CLIExperience.labelCustomFolder.localized, Self.plain(value["customDirectory"]))])
    }

    /// From and to, what is already there and why files cannot be copied.
    func runDirectoryChange(_ value: Value) -> [String] {
        var rows = [(Messages.CLIExperience.labelFrom.localized, Self.plain(value["source"])), (Messages.CLIExperience.labelTo.localized, Self.plain(value["target"]))]
        if path.last == "relocate" {
            let instances = index(.instance)
            rows.append((Messages.CLIExperience.labelInstances.localized, value["instances"].elements.map { reference($0, in: instances) }.joined(separator: ", ")))
            return change(value, rows)
        }
        rows.append((Messages.CLIExperience.labelContents.localized, TextFormat.contents(files: value["sourceFiles"], bytes: value["sourceBytes"])))
        if (value["targetFiles"].int ?? 0) > 0 { rows.append((Messages.CLIExperience.labelAlreadyThere.localized, TextFormat.contents(files: value["targetFiles"], bytes: value["targetBytes"]))) }
        if let issue = value["copyIssue"].string { rows.append((Messages.CLIExperience.labelCannotCopy.localized, style.warning(Self.plain(.string(issue))))) }
        rows.append((Messages.CLIExperience.labelSharedWith.localized, value["otherInstances"].strings.joined(separator: ", ")))
        return change(value, rows)
    }

    // MARK: Java

    static func javaSource(_ value: Value) -> String {
        switch value.string {
        case "managed"?: Messages.CLIExperience.javaManaged.localized
        case "manual"?: Messages.CLIExperience.javaManual.localized
        case "configuration"?: Messages.CLIExperience.javaConfigured.localized
        case "discovery"?: Messages.CLIExperience.javaDiscovered.localized
        default: plain(value)
        }
    }

    func javaRuntimes(_ value: Value) -> [String] {
        let items = value["items"].elements
        return page(value, items: items, columns: [
            // A runtime that cannot be inspected has no version to show.
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { $0["runtime"] == .null ? style.warning(Messages.CLIExperience.statusUnavailable.localized) : Self.plain($0["runtime"]["version"]) },
            ListColumn(header: Messages.CLIExperience.columnArchitecture.localized, priority: 2) { Self.plain($0["runtime"]["architecture"]) },
            ListColumn(header: Messages.CLIExperience.columnSource.localized, priority: 1) { Self.javaSource($0["source"]) },
            ListColumn(header: Messages.CLIExperience.columnID.localized, priority: 3) { Self.plain($0["managedID"]) },
            ListColumn(header: Messages.CLIExperience.columnVendor.localized, detailOnly: true) { Self.plain($0["runtime"]["vendor"]) },
            ListColumn(header: Messages.CLIExperience.columnPath.localized) { Self.plain($0["path"]) }
        ], problems: items.compactMap { item in item["issue"].string.map { (Self.plain(item["path"]), Self.plain(.string($0))) } })
    }

    func availableJava(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnID.localized) { Self.plain($0["id"]) },
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["version"]) },
            ListColumn(header: Messages.CLIExperience.columnArchitecture.localized) { Self.plain($0["architecture"]) }
        ])
    }

    func javaChange(_ value: Value) -> [String] {
        let runtime = value["runtime"] == .null ? value : value["runtime"]
        let version = [runtime["version"], runtime["architecture"], runtime["vendor"]].map(Self.plain).filter { !$0.isEmpty }.joined(separator: " · ")
        let id = runtime["id"].string ?? (path.last == "add" ? nil : request?.operands.first)
        return change(value, [(Messages.CLIExperience.labelID.localized, id ?? ""), (Messages.CLIExperience.labelVersion.localized, version),
                              (Messages.CLIExperience.labelPath.localized, Self.plain(runtime["path"]))])
    }

    func javaRemoval(_ value: Value) -> [String] {
        change(value, [(Messages.CLIExperience.labelID.localized, Self.plain(value["id"])),
                       (Messages.CLIExperience.labelUsedBy.localized, value["references"].strings.joined(separator: ", ")),
                       (Messages.CLIExperience.labelMovedToTrash.localized, Self.plain(value["trashedPath"]))])
    }

    // MARK: Accounts

    static func accountKind(_ account: Value) -> String {
        switch account["kind"].string {
        case "offline"?: Messages.CoreAccount.offlineAccount.localized
        case "microsoft"?: Messages.CoreAccount.microsoftAccount.localized
        case "external"?: Messages.CoreAccount.externalAuth.localized
        default: plain(account["kind"])
        }
    }

    func accounts(_ value: Value) -> [String] {
        let accounts = index(.account)
        return page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnUsername.localized) { Self.plain($0["username"]) },
            ListColumn(header: Messages.CLIExperience.labelType.localized, priority: 1) { Self.accountKind($0) },
            ListColumn(header: Messages.CLIExperience.labelServer.localized, priority: 2) { Self.plain($0["server"]) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { shortID($0["id"], in: accounts) }
        ])
    }

    func account(_ value: Value) -> [String] {
        let account = value["account"] == .null ? value : value["account"]
        return layout.prose(Self.plain(account["username"]), style.bold) + layout.fields([
            (Messages.CLIExperience.labelType.localized, Self.accountKind(account)),
            (Messages.CLIExperience.labelID.localized, Self.plain(account["id"])),
            (Messages.CLIExperience.labelPlayerUUID.localized, Self.plain(account["uuid"])),
            (Messages.CLIExperience.labelServer.localized, Self.plain(account["server"]))
        ])
    }

    func accountChange(_ value: Value) -> [String] {
        let account = value["account"] == .null ? value : value["account"], accounts = index(.account)
        var rows: [(String, String)] = []
        // A refresh names its account among the targets already.
        if path.last != "refresh" {
            rows.append((Messages.CLIExperience.labelAccount.localized, known(account["id"], in: accounts) ? reference(account["id"], in: accounts) : Self.plain(account["username"])))
        }
        return change(value, rows + [(Messages.CLIExperience.labelType.localized, Self.accountKind(account))])
    }

    /// The browser step of a Microsoft sign-in, or the profiles of a third-party one.
    func loginStart(_ value: Value) -> [String] {
        if value["dryRun"] == .bool(true) { return change(value, [(Messages.CLIExperience.labelProvider.localized, Self.plain(value["provider"]))]) }
        let flow = Self.plain(value["flowID"]), complete = ["account", "login", "complete", flow]
        var lines: [String]
        if let url = value["verificationURL"].string {
            lines = layout.prose(Messages.CLIExperience.loginOpen(url, Self.plain(value["userCode"])).localized, style.bold)
            lines += layout.fields([(Messages.CLIExperience.labelCode.localized, style.bold(Self.plain(value["userCode"]))), (Messages.CLIExperience.labelExpires.localized, TextFormat.date(value["expiresAt"]))])
            return lines + [Messages.CLIExperience.nextAction(command(complete)).localized]
        }
        lines = layout.prose(Messages.CLIExperience.loginSignedIn(Self.plain(value["server"])).localized, style.good)
        lines += layout.fields([(Messages.CLIExperience.labelExpires.localized, TextFormat.date(value["expiresAt"]))])
        let profiles = value["profiles"].elements
        guard value["selectedProfile"] == .null, !profiles.isEmpty else { return lines + [Messages.CLIExperience.nextAction(command(complete)).localized] }
        lines += layout.prose(Messages.CLIExperience.chooseProfile.localized) + layout.fields(profiles.map { (Self.plain($0["name"]), Self.plain($0["id"])) })
        return lines + profiles.map { Messages.CLIExperience.nextAction(command(complete + ["--profile", Self.plain($0["id"])])).localized }
    }

    func serviceKey(_ value: Value) -> [String] {
        if value["custom"] == .bool(true) { return layout.prose(Messages.CLIExperience.serviceKeyCustom.localized) }
        if value["bundled"] == .bool(true) { return layout.prose(Messages.CLIExperience.serviceKeyBundled.localized) }
        return layout.prose(Messages.CLIExperience.serviceKeyMissing.localized, style.warning) + [Messages.CLIExperience.nextAction(command(["account", "service-key", "set", "--stdin"])).localized]
    }

    // MARK: Servers

    private var serverEntryColumns: [ListColumn] {
        [ListColumn(header: "#") { Self.atom($0["id"]) },
         ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) },
         ListColumn(header: Messages.CLIExperience.labelAddress.localized) { Self.plain($0["address"]) },
         ListColumn(header: Messages.CLIExperience.columnResourcePacks.localized, priority: 1) { ServerResourcePacks(rawValue: $0["resourcePacks"].string ?? "")?.title ?? Self.plain($0["resourcePacks"]) }]
    }

    private func invalidAddresses(_ items: [Value]) -> [(String, String)] {
        items.filter { $0["validAddress"] == .bool(false) }.map { (Self.atom($0["id"]) + " " + Self.plain($0["name"]), Messages.CLIExperience.invalidAddress.localized) }
    }

    /// Saved servers, or the list one instance shows in the game.
    func servers(_ value: Value) -> [String] {
        let items = value["items"].elements
        if request?.string("instance") != nil { return page(value, items: items, columns: serverEntryColumns, problems: invalidAddresses(items)) }
        let instances = index(.instance)
        return page(value, items: items, columns: [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) + ($0["favorite"] == .bool(true) ? " ★" : "") },
            ListColumn(header: Messages.CLIExperience.labelAddress.localized) { Self.plain($0["address"]) },
            ListColumn(header: Messages.CLIExperience.labelInstances.localized, priority: 1) { $0["instanceIDs"].elements.map { reference($0, in: instances) }.joined(separator: ", ") },
            ListColumn(header: Messages.CLIExperience.labelNotes.localized, detailOnly: true) { Self.plain($0["notes"]) }
        ])
    }

    func serverPreference(_ value: Value) -> [String] {
        let status = [value["favorite"] == .bool(true) ? Messages.CLIExperience.statusFavorite.localized : nil, value["saved"] == .bool(true) ? Messages.CLIExperience.statusSaved.localized : nil]
        return change(value, [(Messages.CLIExperience.labelAddress.localized, Self.plain(value["address"])), (Messages.CLIExperience.labelName.localized, Self.plain(value["name"])),
                              (Messages.CLIExperience.labelStatus.localized, status.compactMap { $0 }.joined(separator: " · ")), (Messages.CLIExperience.labelNotes.localized, Self.plain(value["notes"])),
                              (Messages.CLIExperience.labelPreferredInstance.localized, value["preferredInstanceID"] == .null ? "" : reference(value["preferredInstanceID"], in: index(.instance)))])
    }

    /// An edit of an instance's server list, with the list as it is now.
    func serverListChange(_ value: Value) -> [String] {
        let items = value["items"].elements
        var lines = change(value) + layout.table(serverEntryColumns, items).lines
        if layout.details { lines += layout.fields([(Messages.CLIExperience.labelRevision.localized, Self.atom(value["revision"]))], indent: 0) }
        return lines
    }

    /// Whether a server answers, who is on it and how it describes itself.
    func serverStatus(_ value: Value) -> [String] {
        var lines = layout.prose(Messages.CLIExperience.serverOnline(Self.plain(value["address"])).localized, style.good)
        let players = value["online"].int.map { online in value["maximum"].int.map { Messages.CLIExperience.playersOf(String(online), String($0)).localized } ?? String(online) } ?? ""
        let latency = value["latencyMilliseconds"].int.map {
            Measurement(value: Double($0), unit: UnitDuration.milliseconds).formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(TextFormat.locale))
        } ?? ""
        lines += layout.fields([(Messages.CLIExperience.labelPlayers.localized, players), (Messages.CLIExperience.labelOnlineNow.localized, value["playerSample"].strings.joined(separator: ", ")),
                                (Messages.CLIExperience.labelVersion.localized, Self.plain(value["version"])), (Messages.CLIExperience.labelLatency.localized, latency)])
        // Formatting codes such as §a are for the game, not the terminal.
        let description = (value["description"].string ?? "").replacingOccurrences(of: "§.", with: "", options: .regularExpression)
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines += [""] + layout.paragraph(Self.printable(description), indent: 2) }
        if layout.details { lines += layout.fields([(Messages.CLIExperience.labelQueried.localized, TextFormat.date(value["queriedAt"]))]) }
        return lines
    }

    /// Text that may span lines, with other control characters escaped.
    static func printable(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { plain(.string($0)) }.joined(separator: "\n")
    }
}
