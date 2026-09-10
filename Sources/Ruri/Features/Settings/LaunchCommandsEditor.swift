import SwiftUI
import RuriCore

struct LaunchCommandsEditor: View {
    @Binding var commands: LaunchCommands
    var body: some View {
        Toggle("运行自定义启动命令", isOn: $commands.enabled)
        if commands.enabled || !commands.isEmpty {
            Group {
                Text("启动前命令").font(.headline)
                SettingsTextArea(title: "启动前命令", prompt: "在这里输入 shell 命令；留空跳过", text: $commands.before)
                Text("游戏准备完成后运行。命令成功结束才会启动游戏，失败或超时会停止本次启动。").font(.caption).foregroundStyle(.secondary)
                Text("退出后命令").font(.headline)
                SettingsTextArea(title: "退出后命令", prompt: "在这里输入 shell 命令；留空跳过", text: $commands.after)
                Text("游戏自行退出后运行，包括崩溃退出。手动终止游戏时跳过；命令结果单独显示在日志中。").font(.caption).foregroundStyle(.secondary)
                SettingsNumberField(title: "每条命令最长运行时间", value: $commands.timeoutSeconds, unit: "秒")
                Text("包装命令").font(.headline)
                SettingsTextArea(title: "包装命令", prompt: "可执行文件与参数；留空直接运行 Java", text: $commands.wrapper)
                Text("Ruri 会把 Java 路径和游戏启动参数追加在后面。此处不解析 shell 管道；自定义脚本应使用 exec \"$@\" 转交启动。").font(.caption).foregroundStyle(.secondary)
            }.disabled(!commands.enabled)
            DisclosureGroup("可用变量与填写示例") {
                Text("前后命令由 /bin/sh 在游戏运行目录中执行。路径变量请加双引号。").font(.caption).foregroundStyle(.secondary)
                Text(#"printf '%s\n' "$RURI_GAME_DIRECTORY""#).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("RURI_GAME_DIRECTORY：游戏运行目录\nRURI_INSTANCE_DIRECTORY：实例配置目录\nRURI_INSTANCE_NAME / RURI_INSTANCE_ID：实例名称和标识\nRURI_GAME_VERSION：游戏版本\nRURI_JAVA：Java 可执行文件\nRURI_EXIT_CODE / RURI_EXIT_REASON：游戏退出码和原因，仅退出后命令可用").font(.caption).textSelection(.enabled)
                Text("包装命令可用 ${RURI_GAME_DIRECTORY} 等同名占位符；含空格的参数加引号。只运行自己了解的命令。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
