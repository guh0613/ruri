import SwiftUI

/// A consistent frame for instance content and save management.
struct InstanceManagementSheet<Controls: View, Content: View, Footer: View>: View {
    let title: String
    let instanceName: String
    @ViewBuilder var controls: Controls
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(instanceName).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).textSelection(.enabled)
                }
                controls
            }.padding(20)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 12)
        }.frame(width: 820, height: 580)
    }
}
