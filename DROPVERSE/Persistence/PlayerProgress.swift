import Foundation

/// Persistent progression (spec §15). Persisted as JSON by `SaveManager`.
/// Decoding tolerates missing keys so older save files keep working after updates.
struct PlayerProgress: Codable, Equatable, Sendable {
    var highestUnlockedStage = 1
    var highestStageReached = 1
    var bestScore = 0
    var totalStagesCleared = 0
    var totalRuns = 0
    var selectedSkin: CharacterSkinID = .neonReactor
    var stageBestScores: [Int: Int] = [:]
    var stageClearCounts: [Int: Int] = [:]
    var tutorialCompleted = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerProgress()
        highestUnlockedStage = try c.decodeIfPresent(Int.self, forKey: .highestUnlockedStage) ?? d.highestUnlockedStage
        highestStageReached = try c.decodeIfPresent(Int.self, forKey: .highestStageReached) ?? d.highestStageReached
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore) ?? d.bestScore
        totalStagesCleared = try c.decodeIfPresent(Int.self, forKey: .totalStagesCleared) ?? d.totalStagesCleared
        totalRuns = try c.decodeIfPresent(Int.self, forKey: .totalRuns) ?? d.totalRuns
        selectedSkin = try c.decodeIfPresent(CharacterSkinID.self, forKey: .selectedSkin) ?? d.selectedSkin
        stageBestScores = try c.decodeIfPresent([Int: Int].self, forKey: .stageBestScores) ?? d.stageBestScores
        stageClearCounts = try c.decodeIfPresent([Int: Int].self, forKey: .stageClearCounts) ?? d.stageClearCounts
        tutorialCompleted = try c.decodeIfPresent(Bool.self, forKey: .tutorialCompleted) ?? d.tutorialCompleted
    }
}
