import SwiftUI

struct PauseView: View {
    let game: GameCoordinator

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {} // absorb taps so they never reach the scene

            VStack(spacing: 12) {
                Text("PAUSED")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(NeonPalette.textPrimary.color)
                    .shadow(color: NeonPalette.cyan.opacity(0.6), radius: 10)
                NeonLabel(text: "STAGE \(game.hud.stage) · \(game.hud.difficulty.displayName)")
                    .padding(.bottom, 6)

                Button("RESUME") { game.resume() }
                    .buttonStyle(NeonButtonStyle(prominent: true))
                Button("RESTART STAGE") { game.retryStage() }
                    .buttonStyle(NeonButtonStyle(tint: NeonPalette.magenta.color))
                Button("MAIN MENU") { game.exitToMenu() }
                    .buttonStyle(NeonButtonStyle(tint: NeonPalette.textSecondary.color))
            }
            .padding(24)
            .holographicPanel()
        }
    }
}
