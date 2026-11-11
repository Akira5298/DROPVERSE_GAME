import SwiftUI

/// Glowing neon button used across menus.
struct NeonButtonStyle: ButtonStyle {
    var tint: Color = NeonPalette.cyan.color
    var prominent = false
    var minWidth: CGFloat = 210

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(prominent ? Color.black : NeonPalette.textPrimary.color)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minWidth: minWidth)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(NeonPalette.panel.opacity(0.85)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(configuration.isPressed ? 1 : 0.75), lineWidth: 1.5)
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.9 : 0.45), radius: configuration.isPressed ? 14 : 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Semi-transparent "holographic" panel with a gradient edge.
struct HolographicPanel: ViewModifier {
    var tint: Color = NeonPalette.cyan.color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NeonPalette.panel.opacity(0.82))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [tint.opacity(0.8), NeonPalette.magenta.opacity(0.5), tint.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2)
            }
            .shadow(color: tint.opacity(0.25), radius: 18)
    }
}

extension View {
    func holographicPanel(tint: Color = NeonPalette.cyan.color) -> some View {
        modifier(HolographicPanel(tint: tint))
    }
}

/// Small monospaced label used for section headers and stats.
struct NeonLabel: View {
    let text: String
    var color: Color = NeonPalette.textSecondary.color
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// The DROPVERSE wordmark with chromatic offset.
struct TitleWordmark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Text("DROPVERSE")
                .foregroundStyle(NeonPalette.magenta.opacity(0.7))
                .offset(x: 2.5, y: 1.5)
            Text("DROPVERSE")
                .foregroundStyle(
                    LinearGradient(colors: [NeonPalette.cyan.color, NeonPalette.textPrimary.color, NeonPalette.magenta.color],
                                   startPoint: .leading, endPoint: .trailing))
        }
        .font(.system(size: size, weight: .black, design: .rounded))
        .tracking(3)
        .shadow(color: NeonPalette.cyan.opacity(0.6), radius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DROPVERSE")
    }
}
