import Foundation

enum ParticleIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var multiplier: Double {
        switch self {
        case .low: return 0.35
        case .medium: return 0.7
        case .high: return 1.0
        }
    }
}

/// Visual beat subdivisions for the Rhythm Timing Guide (never affects gameplay).
enum BeatSubdivision: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, half, quarter

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .half: return "1/2 Beat"
        case .quarter: return "1/4 Beat"
        }
    }
}

/// User-facing settings. Persisted as JSON by `SaveManager`; decoding tolerates missing keys
/// so adding settings never wipes a player's existing preferences.
struct GameSettings: Codable, Equatable, Sendable {
    var musicVolume: Double = 0.8
    var sfxVolume: Double = 0.8
    var particleIntensity: ParticleIntensity = .high
    var reducedFlashing = false
    var reducedMotion = false
    /// 0 = off, 1 = full.
    var cameraShake: Double = 1.0
    /// Audio/visual timing offset. Positive values shift visuals (world, guides) later.
    var audioOffsetMilliseconds: Double = 0
    var showPerformanceOverlay = false

    // Rhythm Assistance
    var showBeatGrid = false
    var showTapGuides = false
    var beatSubdivision: BeatSubdivision = .off
    /// 0.2 ... 1.0
    var guideOpacity: Double = 0.65
    var showTimingJudgments = true
    /// Subtracted from touch timestamps before judging (screen/touch latency compensation).
    var inputLatencyMilliseconds: Double = 0

    // Developer
    var showPhysicsDebug = false
    var showCollisionBounds = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        musicVolume = try v(.musicVolume, d.musicVolume)
        sfxVolume = try v(.sfxVolume, d.sfxVolume)
        particleIntensity = try v(.particleIntensity, d.particleIntensity)
        reducedFlashing = try v(.reducedFlashing, d.reducedFlashing)
        reducedMotion = try v(.reducedMotion, d.reducedMotion)
        cameraShake = try v(.cameraShake, d.cameraShake)
        audioOffsetMilliseconds = try v(.audioOffsetMilliseconds, d.audioOffsetMilliseconds)
        showPerformanceOverlay = try v(.showPerformanceOverlay, d.showPerformanceOverlay)
        showBeatGrid = try v(.showBeatGrid, d.showBeatGrid)
        showTapGuides = try v(.showTapGuides, d.showTapGuides)
        beatSubdivision = try v(.beatSubdivision, d.beatSubdivision)
        guideOpacity = min(1, max(0.2, try v(.guideOpacity, d.guideOpacity)))
        showTimingJudgments = try v(.showTimingJudgments, d.showTimingJudgments)
        inputLatencyMilliseconds = try v(.inputLatencyMilliseconds, d.inputLatencyMilliseconds)
        showPhysicsDebug = try v(.showPhysicsDebug, d.showPhysicsDebug)
        showCollisionBounds = try v(.showCollisionBounds, d.showCollisionBounds)
    }
}
