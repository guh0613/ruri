import RuriLocalization
import SwiftUI
import RuriCore

/// What the next launch of this instance would add: the collector as the
/// headline, the Java it runs on, then each option as a chip whose reason
/// shows on hover. The heap, including any raise for ZGC, is the memory card's.
struct JVMTuningPreviewCard: View {
    let java: JavaRuntime?
    /// Nil while the Java and its flags are looked up.
    let tuning: JVMTuning?
    let jvmArguments: String

    var body: some View {
        Group {
            if let tuning { content(tuning) } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(.vertical, 6)
    }

    private func content(_ tuning: JVMTuning) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(collectorTitle(tuning))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(tuning.collector == nil ? Color.secondary : Color.primary)
                    .contentTransition(.opacity)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if !tuning.arguments.isEmpty {
                WrappingLayout(spacing: 6) {
                    ForEach(tuning.arguments, id: \.value) { chip($0) }
                }
            }
            ForEach(visibleNotes(tuning), id: \.self) { note in
                Label(note.title, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tuning)
        .accessibilityElement(children: .combine)
    }

    /// The rules' collector, the one the user named, or the JVM's default.
    private func collectorTitle(_ tuning: JVMTuning) -> String {
        if let collector = tuning.collector { return collector.title }
        let named = (try? ArgumentTokenizer.split(jvmArguments))?.last { $0.hasPrefix("-XX:+") && JVMTuning.isCollectorChoice($0) }
        return named.map { String($0.dropFirst("-XX:+Use".count)) } ?? "—"
    }

    private var subtitle: String {
        java.map { "Java \($0.version)" } ?? Messages.AppLaunchSettingsEditor.jvmTuningNoJava.localized
    }

    /// Without a Java there is nothing to probe; the Java line already says so.
    private func visibleNotes(_ tuning: JVMTuning) -> [JVMTuning.Note] {
        tuning.notes.filter { $0 != .disabled && !(java == nil && $0 == .capabilitiesUnknown) }
    }

    private func chip(_ argument: JVMTuning.Argument) -> some View {
        let collector = [.g1, .zgc, .compactHeaders].contains(argument.reason)
        return Text(argument.value)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(collector ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(collector ? Theme.accent : Color.secondary)
            .lineLimit(1).fixedSize()
            .help(argument.reason.title)
    }
}
