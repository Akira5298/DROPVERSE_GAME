import CoreGraphics
import Foundation

/// Shared geometry for the piano-roll world, used by both the SpriteKit grid
/// (in-game) and the SwiftUI backdrop (menus) so they read as one visual system.
enum PianoRollMetrics {
    /// Milestone 1 has no audio; the grid uses this tempo until real beat maps arrive (Milestone 4).
    static let placeholderBPM: Double = 128
    static let beatsPerBar = 4
    static let laneHeight: CGFloat = 24
    static let keyboardWidth: CGFloat = 44

    private static let blackKeyPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    static func isBlackKey(lane: Int) -> Bool {
        blackKeyPitchClasses.contains(((lane % 12) + 12) % 12)
    }

    static func beatDuration(bpm: Double) -> TimeInterval {
        60.0 / bpm
    }

    /// Horizontal distance covered by one beat at a given scroll speed.
    static func beatSpacing(scrollSpeed: CGFloat, bpm: Double) -> CGFloat {
        scrollSpeed * CGFloat(beatDuration(bpm: bpm))
    }

    static func barWidth(scrollSpeed: CGFloat, bpm: Double) -> CGFloat {
        beatSpacing(scrollSpeed: scrollSpeed, bpm: bpm) * CGFloat(beatsPerBar)
    }

    /// Per-stage environment tints. Milestone 3 replaces this with full genre themes.
    static let stageTints: [RGB] = [
        NeonPalette.cyan,
        NeonPalette.magenta,
        NeonPalette.orange,
        NeonPalette.violet,
        NeonPalette.lime,
    ]

    static func tint(forStage stage: Int) -> RGB {
        stageTints[(max(stage, 1) - 1) % stageTints.count]
    }
}
