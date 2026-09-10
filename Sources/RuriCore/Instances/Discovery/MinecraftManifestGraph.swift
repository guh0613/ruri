import Foundation
import CoreFoundation

/// Structural resolution only. Library selection and loader-specific launch
/// repairs are separate from inheritance and HMCL patch composition.
struct MinecraftManifestGraph {
    var value: [String: Any]
    var layers: [[String: Any]]
    var warnings: [String] = []
}

extension MinecraftDirectoryScan {
    mutating func manifestGraph(_ id: String) throws -> MinecraftManifestGraph {
        var ancestors = Set<String>(), count = 0
        return try resolveManifest(id, ancestors: &ancestors, count: &count)
    }

    private mutating func resolveManifest(_ id: String, ancestors: inout Set<String>, count: inout Int) throws -> MinecraftManifestGraph {
        try Task.checkCancellation()
        try Self.checkIdentifier(id)
        guard ancestors.insert(id).inserted, ancestors.count <= 32 else { throw RuriError.message("版本继承存在循环或层级过深。") }
        defer { ancestors.remove(id) }
        let raw = try object(path("versions/\(id)/\(id).json"))
        var isRoot = false
        if let value = raw["root"], !(value is NSNull) {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw RuriError.message("版本清单的 root 标记无效。") }
            isRoot = number.boolValue
        }
        // Folder names are the repository identities. A stale internal id must
        // not redirect a renamed version's client or inheritance resolution.
        if let declared = raw["id"], !(declared is NSNull) { _ = try Self.identifier(declared) }
        let parentID = try Self.identifier(raw["inheritsFrom"])
        let explicitJar = try Self.identifier(raw["jar"])
        if let explicitJar { try Self.checkIdentifier(explicitJar) }
        let patches: [[String: Any]]?
        if let value = raw["patches"], !(value is NSNull) {
            guard let list = value as? [[String: Any]] else { throw RuriError.message("版本补丁清单格式无效。") }
            patches = list
        } else { patches = nil }
        count += 1 + (patches?.count ?? 0)
        guard count <= 1_024 else { throw RuriError.message("版本组件数量超过读取限制。") }
        var graph: MinecraftManifestGraph
        if let parentID {
            graph = try resolveManifest(parentID, ancestors: &ancestors, count: &count)
            graph.value = try Self.compose(parent: graph.value, child: raw, inherited: true)
            graph.layers.append(raw)
        } else if isRoot && patches != nil {
            // HMCL writes resolved fields beside their source patches. With
            // root=true, rebuild from the patches instead of adding both copies.
            graph = .init(value: [:], layers: [])
        } else {
            graph = .init(value: raw, layers: [raw])
        }
        let inheritedJar = try Self.identifier(graph.value["jar"])
        graph.value["jar"] = explicitJar ?? inheritedJar ?? id
        // Swift's sort is stable, but make equal-priority ordering explicit.
        var sorted: [(offset: Int, priority: Int, patch: [String: Any])] = []
        for (offset, patch) in (patches ?? []).enumerated() {
            sorted.append((offset, try Self.patchPriority(patch), patch))
        }
        sorted.sort { first, second in
            first.priority == second.priority ? first.offset < second.offset : first.priority < second.priority
        }
        for entry in sorted {
            let patch = entry.patch
            try Task.checkCancellation()
            // Patches may retain their old inheritsFrom as source metadata.
            // Neither that reference nor nested patches execute recursively.
            if let nested = patch["patches"], !(nested is NSNull), (nested as? [Any])?.isEmpty != true {
                let warning = "补丁还包含嵌套字段；按照 HMCL 规则仅合并顶层补丁，原字段会保留。"
                if !graph.warnings.contains(warning) { graph.warnings.append(warning) }
            }
            graph.value = try Self.compose(parent: graph.value, child: patch, inherited: false)
            graph.layers.append(patch)
        }
        graph.value["id"] = id
        graph.value.removeValue(forKey: "inheritsFrom")
        graph.value.removeValue(forKey: "patches")
        graph.value["libraries"] = try Self.array(graph.value["libraries"], name: "依赖库")
        // HMCL accepts either enum spelling (client/CLIENT). Normalize the
        // effective map without changing the retained source JSON.
        for key in ["downloads", "logging"] {
            if let value = graph.value[key], !(value is NSNull) {
                guard let map = value as? [String: Any] else { throw RuriError.message("版本文件下载信息格式无效。") }
                var normalized: [String: Any] = [:]
                for (name, item) in map {
                    let canonical = name.lowercased()
                    guard normalized[canonical] == nil else { throw RuriError.message("版本文件下载信息包含重复类型：\(canonical)") }
                    normalized[canonical] = item
                }
                graph.value[key] = normalized
            }
        }
        return graph
    }

    private static func compose(parent: [String: Any], child: [String: Any], inherited: Bool) throws -> [String: Any] {
        var result = parent
        // Explicit empty maps replace a parent's map; null means inherit.
        for key in ["mainClass", "minecraftArguments", "assetIndex", "assets", "javaVersion", "downloads", "logging", "type", "time", "releaseTime", "complianceLevel", "generatedLibraries"] {
            if let value = child[key], !(value is NSNull) { result[key] = value }
        }
        if inherited, let jar = try identifier(child["jar"]) { result["jar"] = jar }
        let parentLibraries = try array(parent["libraries"], name: "依赖库")
        let childLibraries = try array(child["libraries"], name: "依赖库")
        // Inheritance prioritizes child libraries; patches append in priority
        // order. Keep rule-distinct declarations for the later library resolver.
        result["libraries"] = inherited ? childLibraries + parentLibraries : parentLibraries + childLibraries
        guard ((result["libraries"] as? [Any])?.count ?? 0) <= 10_000 else { throw RuriError.message("合并后的依赖库数量超过限制。") }
        let compatibility = try array(parent["compatibilityRules"], name: "兼容规则") + array(child["compatibilityRules"], name: "兼容规则")
        if !compatibility.isEmpty { result["compatibilityRules"] = compatibility }
        if let parentArguments = try argumentObject(parent["arguments"]), let childArguments = try argumentObject(child["arguments"]) {
            var merged: [String: Any] = [:]
            for key in ["game", "jvm"] {
                let values = try array(parentArguments[key], name: "启动参数") + array(childArguments[key], name: "启动参数")
                guard values.count <= 16_384 else { throw RuriError.message("合并后的启动参数数量超过限制。") }
                if parentArguments[key] != nil || childArguments[key] != nil { merged[key] = values }
            }
            result["arguments"] = merged
        } else if let childArguments = try argumentObject(child["arguments"]) { result["arguments"] = childArguments }
        let minimum = try [parent["minimumLauncherVersion"], child["minimumLauncherVersion"]].compactMap { value -> Int? in
            guard let value, !(value is NSNull) else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue), number.intValue >= 0 else { throw RuriError.message("清单的最低启动器版本无效。") }
            return number.intValue
        }.max()
        if let minimum { result["minimumLauncherVersion"] = minimum }
        return result
    }

    private static func argumentObject(_ value: Any?) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let object = value as? [String: Any] else { throw RuriError.message("启动参数不是有效对象。") }
        return object
    }
    private static func array(_ value: Any?, name: String) throws -> [Any] {
        guard let value, !(value is NSNull) else { return [] }
        guard let array = value as? [Any], array.count <= 16_384 else { throw RuriError.message("\(name)清单格式或数量无效。") }
        return array
    }
    private static func patchPriority(_ patch: [String: Any]) throws -> Int {
        guard let value = patch["priority"], !(value is NSNull) else { return Int(Int32.min) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue),
              (Int(Int32.min)...Int(Int32.max)).contains(number.intValue) else { throw RuriError.message("版本补丁优先级无效。") }
        return number.intValue
    }
}
