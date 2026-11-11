import CoreGraphics
import Foundation

/// Global constants shared by the scene, coordinator and tests.
/// Physics lives in `Sim` (Game/Simulation/SimConstants.swift).
enum GameConstants {
    /// Fixed simulation step in real seconds (120 Hz). Each step advances k × this in reference time.
    static let fixedTimeStep: TimeInterval = 1.0 / 120.0
    /// Maximum simulation steps processed in one rendered frame (0.5 s of catch-up). Larger
    /// hitches are worked off over the next frames; the simulation is never skipped forward.
    static let maxCatchUpSteps = 60
    /// Points per beat survived.
    static let pointsPerBeat = 10
    static let stageClearBonus = 1_000
    static let padBonus = 50
    static let orbBonus = 100
    /// How often the scene pushes HUD values to SwiftUI (real seconds).
    static let hudUpdateInterval: TimeInterval = 0.1
}
