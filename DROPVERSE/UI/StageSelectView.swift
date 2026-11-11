import SwiftUI

struct StageSelectView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(SaveManager.self) private var save

    private var stageCount: Int { max(24, save.progress.highestUnlockedStage + 6) }

    var body: some View {
        ScreenScaffold(title: "STAGE SELECT",
                       subtitle: "START A RUN FROM ANY UNLOCKED STAGE · SONGS ARE RANDOMIZED INDEPENDENTLY OF STAGE") {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                    ForEach(1...stageCount, id: \.self) { stage in
                        StageTile(stage: stage,
                                  unlocked: stage <= save.progress.highestUnlockedStage,
                                  bestScore: save.progress.stageBestScores[stage],
                                  clears: save.progress.stageClearCounts[stage] ?? 0) {
                            app.play(fromStage: stage)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct StageTile: View {
    let stage: Int
    let unlocked: Bool
    let bestScore: Int?
    let clears: Int
    let action: () -> Void

    var body: some View {
        let tier = DifficultyTier(stage: stage)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(stage)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(unlocked ? NeonPalette.textPrimary.color : NeonPalette.textSecondary.opacity(0.5))
                    Spacer()
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(NeonPalette.textSecondary.color)
                    }
                }
                NeonLabel(text: tier.displayName, color: tier.accent.color.opacity(unlocked ? 1 : 0.4), size: 10)
                NeonLabel(text: bestScore.map { "BEST \($0.formatted())" } ?? "BEST —", size: 10)
                NeonLabel(text: "CLEARS \(clears)", size: 10)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(NeonPalette.panel.opacity(unlocked ? 0.9 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tier.accent.color.opacity(unlocked ? 0.7 : 0.15), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("Stage \(stage), \(tier.displayName), \(unlocked ? "unlocked" : "locked")")
    }
}
