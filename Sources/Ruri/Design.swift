import SwiftUI
import RuriCore

enum Theme {
    static let accent = Color(red: 0.23, green: 0.47, blue: 0.39)
    static let ink = Color(red: 0.13, green: 0.24, blue: 0.21)
    static let sand = Color(red: 0.92, green: 0.90, blue: 0.84)
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.065), lineWidth: 1))
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 27, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct TagPill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.1), in: Capsule()).foregroundStyle(color) }
}

struct InstanceIcon: View {
    let loader: LoaderKind
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: loader.symbol).font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(loader == .vanilla ? Theme.accent : Color.orange.opacity(0.8))
            .frame(width: size, height: size)
            .background((loader == .vanilla ? Theme.accent : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.26))
    }
}

/// A native vector landscape; it scales with the window and contains no downloaded art.
struct Landscape: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.81, green: 0.88, blue: 0.81), Color(red: 0.95, green: 0.93, blue: 0.82)]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.74, y: h * 0.13, width: 69, height: 69)), with: .color(Color(red: 0.98, green: 0.85, blue: 0.55)))
            func polygon(_ points: [(Double, Double)], _ color: Color) {
                var path = Path(); path.move(to: CGPoint(x: points[0].0 * w, y: points[0].1 * h))
                for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.0 * w, y: p.1 * h)) }; path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            polygon([(0.30,1),(0.45,0.57),(0.51,0.57),(0.51,0.48),(0.59,0.48),(0.59,0.38),(0.64,0.38),(0.64,0.45),(0.70,0.45),(0.80,0.70),(1,0.61),(1,1)], Color(red: 0.58, green: 0.71, blue: 0.63))
            polygon([(0.45,1),(0.62,0.68),(0.67,0.68),(0.67,0.60),(0.73,0.60),(0.73,0.53),(0.78,0.53),(0.78,0.68),(0.86,0.68),(0.91,0.80),(1,0.77),(1,1)], Color(red: 0.37, green: 0.57, blue: 0.47))
            polygon([(0,0.89),(0.15,0.84),(0.31,0.91),(0.44,0.85),(0.56,0.94),(0.68,0.85),(0.78,0.95),(1,0.89),(1,1),(0,1)], Color(red: 0.22, green: 0.40, blue: 0.33))
            func tree(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat) {
                let color = Color(red: 0.19, green: 0.37, blue: 0.29)
                context.fill(Path(CGRect(x: x - 3 * scale, y: y - 35 * scale, width: 6 * scale, height: 42 * scale)), with: .color(color))
                for i in 0..<3 {
                    let width = CGFloat(34 - i * 8) * scale
                    context.fill(Path(CGRect(x: x - width / 2, y: y - CGFloat(30 + i * 14) * scale, width: width, height: 18 * scale)), with: .color(color))
                }
            }
            tree(w * 0.86, h * 0.88, 1.45); tree(w * 0.94, h * 0.92, 1.0); tree(w * 0.55, h * 0.95, 0.6)
        }.accessibilityHidden(true)
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Theme.accent).padding(.bottom, 6)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
        }.frame(maxWidth: .infinity).padding(.vertical, 45)
    }
}
