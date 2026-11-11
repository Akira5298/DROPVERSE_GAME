import SwiftUI

struct GameOverView: View {
    let game: GameCoordinator
    let result: RunResult

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SIGNAL LOST")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(NeonPalette.hazard.color)
                        .shadow(color: NeonPalette.hazard.opacity(0.7), radius: 12)
                    if result.isNewBest {
                        NeonLabel(text: "NEW BEST RECORD", color: NeonPalette.lime.color, size: 13)
                    }
                    statRow("FINAL SCORE", result.finalScore.formatted())
                    statRow("STAGES CLEARED", "\(result.stagesCleared)")
                    statRow("FAILED ON", "STAGE \(result.failedStage)")
                    statRow("HIGHEST STAGE", "\(result.highestStageReached)")
                    statRow("BEST RECORD", result.bestScore.formatted())
                    statRow("TRACK", "\(result.trackTitle) — \(result.artist)")
                }

                VStack(spacing: 12) {
                    Button("RETRY STAGE") { game.retryStage() }
                        .buttonStyle(NeonButtonStyle(prominent: true))
                    Button("NEW RUN") { game.newRun() }
                        .buttonStyle(NeonButtonStyle(tint: NeonPalette.magenta.color))
                    Button("MAIN MENU") { game.exitToMenu() }
                        .buttonStyle(NeonButtonStyle(tint: NeonPalette.textSecondary.color))
                }
            }
            .padding(24)
            .holographicPanel(tint: NeonPalette.hazard.color)
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            NeonLabel(text: label)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(NeonPalette.textPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
