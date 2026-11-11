import Foundation

/// Stage difficulty bands (overhaul spec §1). There is no beginner band any more:
/// stage 1 already mixes obstacle types and both Runner and Surfer movement.
enum DifficultyTier: String, CaseIterable, Codable, Sendable {
    case challenging
    case hard
    case veryHard
    case expert

    init(stage: Int) {
        switch stage {
        case ...3: self = .challenging
        case 4...8: self = .hard
        case 9...15: self = .veryHard
        default: self = .expert
        }
    }

    var displayName: String {
        switch self {
        case .challenging: return "CHALLENGING"
        case .hard: return "HARD"
        case .veryHard: return "VERY HARD"
        case .expert: return "EXPERT"
        }
    }

    var accent: RGB {
        switch self {
        case .challenging: return NeonPalette.cyan
        case .hard: return NeonPalette.violet
        case .veryHard: return NeonPalette.orange
        case .expert: return NeonPalette.hazard
        }
    }

    /// Relative pick weight per pattern difficulty (1...4). Missing = not eligible.
    var patternWeights: [Int: Double] {
        switch self {
        case .challenging: return [1: 1.0, 2: 0.7]
        case .hard: return [1: 0.2, 2: 1.0, 3: 0.8]
        case .veryHard: return [2: 0.5, 3: 1.0, 4: 0.6]
        case .expert: return [2: 0.2, 3: 0.8, 4: 1.2]
        }
    }

    /// Minimum beats between patterns. Every pattern pair was validated with a 1-beat gap.
    var gapBeats: Int {
        self == .challenging ? 2 : 1
    }

    var easier: DifficultyTier {
        switch self {
        case .challenging, .hard: return .challenging
        case .veryHard: return .hard
        case .expert: return .veryHard
        }
    }
}
