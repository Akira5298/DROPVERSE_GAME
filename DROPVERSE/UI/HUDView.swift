import SwiftUI

/// Gameplay HUD. Lives in the band above the ceiling (scene y > 600), so it never covers
/// the playfield. Only the pause button accepts touches.
struct HUDView: View {
    let game: GameCoordinator

    var body: some View {
        let hud = game.hud
        VStack {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(hud.isTutorial ? "TUTORIAL" : "STAGE \(hud.stage)")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(NeonPalette.textPrimary.color)
                        if !hud.isTutorial {
                            NeonLabel(text: hud.difficulty.displayName, color: hud.difficulty.accent.color, size: 10)
                        }
                        ModeChip(mode: hud.mode)
                    }
                    Text("\(hud.trackTitle) — \(hud.artist)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(NeonPalette.textSecondary.color)
                        .lineLimit(1)
                }
                .allowsHitTesting(false)

                Spacer(minLength: 8)

                ProgressBar(progress: hud.progress, tint: hud.difficulty.accent.color)
                    .frame(width: 200, height: 6)
                    .padding(.top, 8)
                    .allowsHitTesting(false)

                Spacer(minLength: 8)

                Text(hud.score.formatted())
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NeonPalette.cyan.color)
                    .shadow(color: NeonPalette.cyan.opacity(0.6), radius: 6)
                    .allowsHitTesting(false)

                Button {
                    game.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NeonPalette.textPrimary.color)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(NeonPalette.panel.opacity(0.8)))
                        .overlay(Circle().strokeBorder(NeonPalette.cyan.opacity(0.6), lineWidth: 1))
                }
                .accessibilityLabel("Pause")
                .disabled(game.phase != .playing)
            }
            Spacer().allowsHitTesting(false)
            if let hint = hud.hint {
                Text(hint)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NeonPalette.textPrimary.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(NeonPalette.panel.opacity(0.85)))
                    .overlay(Capsule().strokeBorder(NeonPalette.lime.opacity(0.7), lineWidth: 1))
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.2), value: hud.hint)
    }
}

/// Shows the current movement mode so context changes are always communicated.
private struct ModeChip: View {
    let mode: MovementMode

    var body: some View {
        let (label, color): (String, Color) = {
            switch mode {
            case .cube: return ("RUN", NeonPalette.lime.color)
            case .ship: return ("SURF", NeonPalette.magenta.color)
            case .wave: return ("WAVE", NeonPalette.cyan.color)
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
            .accessibilityLabel("Mode \(label)")
    }
}

private struct ProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
                    .shadow(color: tint.opacity(0.8), radius: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Stage progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
