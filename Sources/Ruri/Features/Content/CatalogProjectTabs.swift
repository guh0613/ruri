import SwiftUI
import RuriLocalization

/// Full-width section navigation, separate from the compact filter controls.
struct CatalogProjectTabs: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            tab("overview", title: Messages.Discovery.overview.localized)
            tab("versions", title: Messages.Discovery.versions.localized)
            tab("gallery", title: Messages.Discovery.gallery.localized)
        }
        .background(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Messages.Discovery.projectSections.localized)
    }

    private func tab(_ id: String, title: String) -> some View {
        Button { selection = id } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selection == id ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle().fill(selection == id ? Color.accentColor : .clear)
                        .frame(width: 44, height: 2)
                }
        }
        .buttonStyle(CatalogButtonStyle())
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

/// Keep list and card buttons flat; feedback belongs to the pressed control,
/// rather than an extra rounded panel following the pointer during scrolling.
struct CatalogButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}
