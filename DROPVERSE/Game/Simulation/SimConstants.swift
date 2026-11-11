import Foundation

/// Gameplay physics in *reference units*: points and reference seconds (tau).
///
/// One beat is always `beatTau` reference seconds. Real time is converted with
/// `k = foldedBPM / 128`, so every pattern is the same in beat space at any tempo.
/// These values are mirrored in `Tools/dropverse_sim.py` (the offline validator).
/// Change both together.
enum Sim {
    static let referenceBPM: Double = 128
    static let beatTau: Double = 60.0 / 128.0
    static let speed: Double = 320                  // x per tau at speed multiplier 1
    static let beatX: Double = speed * beatTau      // 150 pt per beat
    static let floorY: Double = 150
    static let ceilingY: Double = 600
    static let playHeight: Double = ceilingY - floorY

    static let halfBig: Double = 22
    static let halfMini: Double = 13

    // Cube (runner)
    static let gravity: Double = 1850
    static let jump: Double = 620
    static let jumpMini: Double = 520
    /// Second (air) jump. Vertical velocity is *reset* to this value, never added, so the
    /// double jump height is the same whether it is used while rising or falling.
    static let jump2: Double = 650
    static let jump2Mini: Double = 545
    /// Jumps available after a valid landing (ground jump + one air jump).
    static let maxJumps = 2
    static let holdMax: Double = 0.18
    static let holdScale: Double = 0.45
    static let coyote: Double = 0.08
    static let buffer: Double = 0.10
    static let terminal: Double = 1000

    // Ship (surfer)
    static let shipGravity: Double = 1200
    static let shipThrust: Double = 2200
    static let shipMax: Double = 430

    // Wave
    static let waveSlope: Double = 1
    static let waveSlopeMini: Double = 2

    // Interactives
    static let padYellow: Double = 860
    static let padPink: Double = 700
    static let orbYellow: Double = 680
    static let orbPink: Double = 560
    static let orbGravityPush: Double = 250

    // Spikes: visual triangle is spikeWidth wide; the lethal core is narrower (fair hitbox).
    static let spikeWidth: Double = 44
    static let spikeCoreHalf: Double = spikeWidth * 0.18
    static let spikeCoreHeight: Double = spikeWidth * 0.6

    static let landTolerance: Double = 6
    /// Ledge catch: a side contact whose previous-step position was at most this far below a
    /// surface snaps onto it instead of killing (a corner clip, not a wall hit).
    static let edgeSnap: Double = 12
    /// Falling platforms accelerate downward at this rate once released.
    static let fallGravity: Double = 1400
    static let triggerPad: Double = 6
    static let killMargin: Double = 120

    /// Tempo folding range: BPMs are halved/doubled into [90, 180).
    static let minFoldedBPM: Double = 90
    static let maxFoldedBPM: Double = 180

    static func foldBPM(_ bpm: Double) -> Double {
        guard bpm.isFinite, bpm > 0 else { return referenceBPM }
        var b = bpm
        while b >= maxFoldedBPM { b /= 2 }
        while b < minFoldedBPM { b *= 2 }
        return b
    }

    /// Tempo factor: reference seconds per real second.
    static func tempoFactor(bpm: Double) -> Double {
        foldBPM(bpm) / referenceBPM
    }
}
