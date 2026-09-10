import SwiftUI
import AppKit
import RuriCore

struct CurseForgeSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        Section("CurseForge") {
            LabeledContent("API Key", value: model.curseForgeConfigured ? "已保存在钥匙串" : "尚未配置")
            SecureField(model.curseForgeConfigured ? "输入新 Key 以替换" : "输入 API Key", text: $key)
            HStack {
                Button("保存到钥匙串") {
                    do { try CurseForgeKeyStore.save(key); key = ""; error = nil; model.curseForgeConfigured = true }
                    catch { self.error = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.curseForgeConfigured {
                    Button("移除 Key") {
                        do { try CurseForgeKeyStore.remove(); key = ""; error = nil; model.curseForgeConfigured = false }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("用于 CurseForge 内容搜索、整合包下载与更新。Key 保存在 macOS 钥匙串中，实例导出不包含它。").font(.caption).foregroundStyle(.secondary)
            Link("CurseForge 第三方 API 申请说明", destination: URL(string: "https://support.curseforge.com/support/solutions/articles/9000208346")!)
        }
    }
}

/// Local files are copied into the resumable cache after verification, so a
/// dismissed file panel never leaves a security-scoped URL in a future task.
