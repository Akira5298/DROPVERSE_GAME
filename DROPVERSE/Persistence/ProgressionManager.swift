import Foundation

/// Pure progression rules, kept separate from storage so they are unit-testable.
enum ProgressionManager {
    /// Clearing stage N unlocks stage N + 1 as a starting point.
    static func recordStageCleared(_ stage: Int, score: Int, progress: inout PlayerProgress) {
        progress.highestUnlockedStage = max(progress.highestUnlockedStage, stage + 1)
        progress.highestStageReached = max(progress.highestStageReached, stage + 1)
        progress.totalStagesCleared += 1
        progress.stageClearCounts[stage, default: 0] += 1
        progress.stageBestScores[stage] = max(progress.stageBestScores[stage] ?? 0, score)
    }

    /// Records the end of a run. Returns true when `finalScore` is a new best.
    @discardableResult
    static func recordRunEnded(stageReached: Int, finalScore: Int, progress: inout PlayerProgress) -> Bool {
        progress.highestStageReached = max(progress.highestStageReached, stageReached)
        progress.totalRuns += 1
        if finalScore > progress.bestScore {
            progress.bestScore = finalScore
            return true
        }
        return false
    }
}
