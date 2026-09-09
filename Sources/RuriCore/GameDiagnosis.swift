import Foundation

public struct GameDiagnosticDocument: Identifiable, Sendable {
    public enum Kind: String, Sendable { case preparation, output, gameReport, jvmReport }
    public let id: String
    public let relativePath: String?
    public let title: String
    public let kind: Kind
    public let text: String
    public var isTail = false
    public var truncated = false
}

public struct GameDiagnosis: Sendable {
    public struct Evidence: Identifiable, Sendable {
        public let documentID: String
        public let line: Int
        public let excerpt: String
        public var id: String { "\(documentID):\(line)" }
    }
    public enum Action: String, CaseIterable, Sendable {
        case settings, mods, accounts, repair, files, collect
        public var title: String {
            switch self {
            case .settings: "检查实例设置"
            case .mods: "管理模组"
            case .accounts: "检查账号"
            case .repair: "修复安装文件"
            case .files: "查看运行文件"
            case .collect: "收集诊断报告"
            }
        }
    }
    public struct Finding: Identifiable, Sendable {
        public enum Confidence: String, Sendable { case reported = "日志明确报告", possible = "需要验证的线索" }
        public let id: String
        public let title: String
        public let explanation: String
        public let confidence: Confidence
        public let steps: [String]
        public let actions: [Action]
        public var evidence: [Evidence]
    }
    public let sessionID: UUID
    public let title: String
    public let summary: String
    public let facts: [String]
    public let findings: [Finding]
    public let documents: [GameDiagnosticDocument]
    public let limitations: [String]
}

/// Rules describe what a source actually reports, not which mod is guilty.
/// Only this session's saved evidence is read; log text never supplies a path.
public enum GameDiagnosticAnalyzer {
    public static func load(paths: LauncherPaths, session: GameSession) throws -> GameDiagnosis {
        var documents: [GameDiagnosticDocument] = [], limitations: [String] = []
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        if let failure = session.failure {
            documents.append(.init(id: "preparation", relativePath: nil, title: session.stage.title, kind: .preparation, text: failure))
        }
        var budget = 12 * 1_048_576 // Reserve 4 MiB for the session's own output.
        func read(_ relative: String, title: String, kind: GameDiagnosticDocument.Kind, truncated: Bool = false) throws {
            try Task.checkCancellation()
            let url = try LauncherPaths.safePath(relative, within: directory)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw RuriError.message("证据不是普通文件。") }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let size = try handle.seekToEnd(); try handle.seek(toOffset: 0)
            let count = min(budget, 2 * 1_048_576)
            guard count > 0 else { limitations.append("分析读取量已达 16 MiB，未读取 \(title)。"); return }
            let head = try handle.read(upToCount: count) ?? Data(); budget -= head.count
            let partial = size > head.count
            var text = String(decoding: head, as: UTF8.self)
            if partial, let end = text.lastIndex(of: "\n") { text = String(text[..<end]) }
            documents.append(.init(id: relative, relativePath: relative, title: title, kind: kind, text: text, truncated: truncated || partial))
            if partial && kind == .output && budget > 0 {
                let tailCount = min(budget, count)
                try handle.seek(toOffset: max(UInt64(head.count), size - UInt64(tailCount)))
                let tail = try handle.read(upToCount: tailCount) ?? Data(); budget -= tail.count
                let tailText = String(decoding: tail, as: UTF8.self)
                // A tail starts at an arbitrary byte. Discard the incomplete first line.
                documents.append(.init(id: relative + "#tail", relativePath: relative, title: title + "（末段）", kind: kind,
                                       text: String(tailText.drop(while: { $0 != "\n" }).dropFirst()), isTail: true, truncated: true))
            }
            if truncated || partial { limitations.append("\(title) 仅分析有界片段，可能缺少上下文；原有文件未修改。") }
        }
        // Prioritize a crash report over duplicate copies of standard output.
        let reports = session.evidence.sorted { ($0.name == "latest.log" ? 1 : 0, $0.name) < ($1.name == "latest.log" ? 1 : 0, $1.name) }
        for item in reports.prefix(12) {
            guard item.relativePath.hasPrefix("reports/") else { limitations.append("跳过无效证据路径。"); continue }
            let kind: GameDiagnosticDocument.Kind = item.name.hasPrefix("hs_err_pid") ? .jvmReport : item.name.hasPrefix("crash-") ? .gameReport : .output
            do { try read(item.relativePath, title: item.name, kind: kind, truncated: item.truncated) }
            catch is CancellationError { throw CancellationError() }
            catch { limitations.append("未能读取 \(item.name)：\(error.localizedDescription)") }
        }
        if reports.count > 12 { limitations.append("本次有 \(reports.count) 份报告，仅分析前 12 份；其余仍可在运行目录查看。") }
        budget += 4 * 1_048_576
        do { try read("launcher.log", title: "launcher.log", kind: .output) }
        catch is CancellationError { throw CancellationError() }
        catch { limitations.append("未能读取会话日志：\(error.localizedDescription)") }
        return try analyze(session: session, documents: documents, limitations: limitations)
    }

    public static func analyze(session: GameSession, documents: [GameDiagnosticDocument], limitations: [String] = []) throws -> GameDiagnosis {
        var facts = ["最后记录阶段：\(session.stage.title)", "Minecraft \(session.gameVersion) · \(session.loader) \(session.loaderVersion ?? "")",
                     "\(session.java ?? "未记录 Java") · 内存上限 \(session.memoryMB) MB"]
        if let exit = session.exit {
            facts.append("\(exit.reason == .signal ? "终止信号" : "退出码")：\(exit.status)；Ruri 结束请求：\(exit.stopRequested ? "有" : "无")")
        }
        var findings: [GameDiagnosis.Finding] = []
        let externalTermination = session.exit.map { ($0.reason == .signal && [9, 15].contains($0.status)) || ($0.reason == .exit && $0.status == 143) } ?? false
        let canDiagnose = session.state == .failed && !externalTermination
        if canDiagnose {
            for document in documents {
                try Task.checkCancellation()
                let lines = document.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
                var level: String?, crashSectionEnded = false
                for (index, original) in lines.enumerated() {
                    if index % 256 == 0 { try Task.checkCancellation() }
                    let line = String(original.prefix(8192)), lower = line.lowercased()
                    if document.kind == .gameReport && line.contains("A detailed walkthrough of the error") { crashSectionEnded = true }
                    if crashSectionEnded { continue } // A mod list or system description is not the failing stack.
                    if let value = logLevel(line) { level = value }
                    if line.hasPrefix("Exception in thread ") || line.hasPrefix("Error:") || line.hasPrefix("错误:") { level = "FATAL" }
                    let quiet = ["WARN", "INFO", "DEBUG", "TRACE"].contains(level ?? "")
                    if quiet { continue }
                    // JVM reports put all environment data after their initial failure summary.
                    if document.kind == .jvmReport && index > 180 { continue }
                    for rule in rules where rule.needles.contains(where: lower.contains) {
                        if rule.requiresFatalContext && document.kind == .output && level != "ERROR" && level != "FATAL" { continue }
                        let start = max(0, index - 2), end = min(lines.count, index + 7)
                        let excerpt = String(lines[start..<end].joined(separator: "\n").prefix(4096))
                        let evidence = GameDiagnosis.Evidence(documentID: document.id, line: index + 1, excerpt: excerpt)
                        if let existing = findings.firstIndex(where: { $0.id == rule.id }) {
                            if findings[existing].evidence.count < 3 && !findings[existing].evidence.contains(where: { $0.documentID == document.id }) {
                                findings[existing].evidence.append(evidence)
                            }
                        } else {
                            findings.append(.init(id: rule.id, title: rule.title, explanation: rule.explanation, confidence: rule.confidence,
                                                  steps: rule.steps, actions: rule.actions, evidence: [evidence]))
                        }
                    }
                }
            }
        }
        // Keep a specific entrypoint/dependency diagnosis ahead of downstream Mixin/class errors.
        findings.sort { lhs, rhs in
            let li = rules.firstIndex { $0.id == lhs.id } ?? 0, ri = rules.firstIndex { $0.id == rhs.id } ?? 0
            return li < ri
        }
        let summary: String
        if !session.state.isFinished { summary = "本次运行尚无最终退出记录，暂不判断崩溃原因。可继续查看实时日志和进程状态。" }
        else if session.state == .cancelled { summary = "启动已取消，没有证据表明游戏发生了崩溃。" }
        else if session.state == .stopped || session.state == .succeeded { summary = session.exit?.explanation ?? "本次运行已经结束，无需进行崩溃处理。" }
        else if externalTermination { summary = "记录表明进程被结束，但不能确定请求来源，也不能据此断言内存不足或模组冲突。" }
        else if session.exit == nil { summary = "启动在“\(session.stage.title)”阶段失败，游戏尚未产生退出记录。先检查该阶段的错误。" }
        else if findings.isEmpty { summary = "已确认本次异常退出，现有证据尚不能定位原因。保留报告，比根据普通警告修改模组更有帮助。" }
        else { summary = "找到 \(findings.count) 类相关错误。下面保留了原文和处理步骤；错误中出现的模组不一定是唯一原因。" }
        if canDiagnose && session.failure != nil && findings.isEmpty {
            let action: GameDiagnosis.Action = session.stage == .account ? .accounts : .settings
            findings.append(.init(id: "preparation", title: "\(session.stage.title)失败", explanation: "这是启动器记录的准备阶段错误，尚不能归为游戏崩溃。", confidence: .reported,
                                  steps: ["核对下方原始错误以及对应设置，处理后重新启动。", "若仍然失败，收集这次运行记录，以便比较重试前后的错误。"], actions: [action, .collect],
                                  evidence: [.init(documentID: "preparation", line: 1, excerpt: String((session.failure ?? "").prefix(4096)))]))
        }
        return .init(sessionID: session.id, title: session.title, summary: summary, facts: facts, findings: findings, documents: documents, limitations: limitations)
    }

    private struct Rule {
        let id: String, title: String, explanation: String
        let needles: [String]
        var confidence = GameDiagnosis.Finding.Confidence.reported
        var requiresFatalContext = false
        let steps: [String]
        let actions: [GameDiagnosis.Action]
    }
    private static let levelPattern = try! NSRegularExpression(pattern: #"^(?:\[[^\]\r\n]{1,100}\]\s*)?\[(?:[^\]\r\n]*/)?(TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\]"#)
    private static func logLevel(_ text: String) -> String? {
        guard let match = levelPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) { return String(text[range]) }
        }
        return nil
    }
    private static let rules: [Rule] = [
        .init(id: "java-version", title: "Java 无法读取所需的类版本", explanation: "Java 明确报告类文件版本不受支持。游戏、加载器和模组都可能对 Java 有要求。",
              needles: ["java.lang.unsupportedclassversionerror"], steps: ["在实例设置核对 Java，按游戏和整合包要求选择版本。", "如果刚替换过模组，检查该模组是否要求另一代 Java 或 Minecraft。"], actions: [.settings, .mods]),
        .init(id: "jvm-options", title: "Java 启动参数被拒绝", explanation: "虚拟机报告参数或内存上限无效，游戏尚未正常启动。",
              needles: ["unrecognized vm option", "unrecognized option:", "invalid maximum heap size", "improperly specified vm option"], steps: ["核对实例的附加 JVM 参数，保留副本后逐项撤销最近增加的参数。", "确认内存上限与所选 Java 匹配，然后重试。"], actions: [.settings]),
        .init(id: "main-class", title: "找不到游戏启动入口", explanation: "Java 明确报告无法加载主类。版本文件、加载器安装或启动入口需要检查。",
              needles: ["could not find or load main class", "找不到或无法加载主类", "找不到或無法載入主要類別"], steps: ["检查实例所用的游戏与加载器版本，再使用实例的修复功能补全安装文件。", "保留现有配置与存档；若修复后仍失败，附上这次报告。"], actions: [.repair, .settings, .collect]),
        .init(id: "dependencies", title: "加载器拒绝了模组组合", explanation: "加载器报告缺少依赖、版本要求不满足或模组冲突。原文通常包含需要的版本范围。",
              needles: ["incompatible mods found!", "incompatible mod set!", "modresolutionexception:", "missing or unsupported mandatory dependencies:", "missing mandatory dependencies:", "loading errors encountered:"],
              steps: ["按证据中的模组 ID 和版本范围核对依赖，并确认 Minecraft 与加载器版本。", "在模组管理中处理最近的变更；一次只改一组相关依赖，保留恢复余地后重试。"], actions: [.mods, .settings]),
        .init(id: "duplicate-mods", title: "加载器发现重复模组", explanation: "同一个模组被加载多次，可能存在不同版本或重复来源。",
              needles: ["found duplicate mods:", "found a duplicate mod", "duplicate versions for mod id"], steps: ["在模组管理中核对原文列出的文件和版本。", "停用多余的一份后重试；不要同时删掉所有版本。"], actions: [.mods]),
        .init(id: "mod-entrypoint", title: "模组初始化失败", explanation: "加载器指出某个入口或模组实例初始化失败；依赖或其他模组仍可能参与其中。",
              needles: ["could not execute entrypoint stage", "loaderexceptionmodcrash: caught exception from", "failed to create mod instance."],
              steps: ["核对证据中列出的模组、依赖与加载器版本。", "若错误紧随一次更新出现，先核对此前版本；可在模组管理中停用最近加入的模组来验证，之后仍能重新启用。"], actions: [.mods]),
        .init(id: "heap-memory", title: "Java 报告内存耗尽", explanation: "错误上下文出现 OutOfMemoryError；仅凭这一类错误还不能判断应增加哪一种内存。",
              needles: ["java.lang.outofmemoryerror"], confidence: .possible, requiresFatalContext: true,
              steps: ["先查看原文是 Java heap space、Direct buffer memory、Metaspace 还是无法创建线程。", "仅在堆内存不足时考虑调整实例内存，并给 macOS 留出余量；同时检查最近加入的模组或高分辨率资源。"], actions: [.settings, .mods]),
        .init(id: "native-memory", title: "虚拟机无法分配所需内存", explanation: "JVM 报告本机内存分配失败。增大 Java 堆上限可能进一步挤占系统内存。",
              needles: ["there is insufficient memory for the java runtime environment to continue", "could not reserve enough space for"],
              steps: ["检查系统内存压力与其他程序占用，核对是否设置了过大的 Java 堆。", "调整后重新启动；保留 JVM 报告中的分配大小和失败位置供排查。"], actions: [.settings]),
        .init(id: "native-architecture", title: "本地库或 Java 的架构不匹配", explanation: "系统明确报告二进制架构不兼容，需要让 Java 与游戏本地库使用匹配的架构。",
              needles: ["incompatible architecture (have", "bad cpu type in executable"],
              steps: ["核对所选 Java 的 ARM64 / Intel 架构，并使用适用于这套游戏的版本。", "检查提供本地库的模组是否支持当前架构；之后修复实例以重新准备本地库。"], actions: [.settings, .mods]),
        .init(id: "macos-main-thread", title: "窗口初始化违反 macOS 主线程要求", explanation: "Cocoa 或 GLFW 明确报告窗口必须在主线程创建。需要检查 Java、LWJGL 与首线程启动参数的组合。",
              needles: ["glfw may only be used on the main thread", "nswindow should only be instantiated on the main thread", "nswindow drag regions should only be invalidated on the main thread", "glfw error before init: [0x10008]cocoa: failed to find service port for display"],
              steps: ["核对游戏所需的 Java 和加载器版本，检查自定义参数是否影响首线程启动。", "保留报告中的 Java、macOS 与错误原文，便于确认是否需要修正启动器的启动方式。"], actions: [.settings, .collect]),
        .init(id: "config", title: "配置文件读取失败", explanation: "加载器在错误上下文中指出无法读取配置。可能是内容格式、版本差异或文件访问问题。",
              needles: ["failed loading config file"], requiresFatalContext: true,
              steps: ["先查看原文的文件名和底层错误；修改前把该配置复制到别处留作备份。", "按对应模组说明修正配置；需要重新生成时只处理该文件，避免清空整套配置。"], actions: [.files, .mods]),
        .init(id: "mixin", title: "错误上下文中有 Mixin 应用失败", explanation: "这是模组修改游戏代码时的失败线索。文件名或堆栈中的模组不能直接当作唯一责任方。",
              needles: ["mixinapplyerror", "mixin apply for mod", "mixin apply failed", "mixin prepare failed", "critical injection failure"], confidence: .possible, requiresFatalContext: true,
              steps: ["先处理上方明确的依赖或入口错误，再检查这里涉及的模组版本组合。", "通过模组管理逐步停用最近改动的模组来验证，之后仍能重新启用；不要根据单条警告批量删除模组。"], actions: [.mods, .collect]),
        .init(id: "native-crash", title: "JVM 记录了本机崩溃", explanation: "虚拟机报告致命错误；Problematic frame 只是崩溃位置，仍需结合本地库、Java 与系统环境判断原因。",
              needles: ["a fatal error has been detected by the java runtime environment"], steps: ["保留 JVM 报告的错误信号、Problematic frame 与 Java 版本。", "核对所用 Java 和含本地库的模组版本，将报告与复现步骤一起提供给维护者。"], actions: [.settings, .collect]),
        .init(id: "debug-crash", title: "报告注明手动触发调试崩溃", explanation: "Minecraft 报告的描述是手动调试崩溃，不据此推断模组不兼容。",
              needles: ["manually triggered debug crash"], steps: ["若这是有意触发的调试操作，保存所需报告后正常重新启动。"], actions: [.collect])
    ]
}
