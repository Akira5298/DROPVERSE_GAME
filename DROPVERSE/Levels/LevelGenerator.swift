import Foundation

/// Input for generating one stage.
struct StageRequest {
    var stage: Int
    var seed: UInt64
    /// Stage length in folded beats (always whole bars).
    var totalBeats: Int
    /// Tempo factor k (reference seconds per real second).
    var tempoFactor: Double = 1
    /// Optional per-bar energy (0...1) from music analysis.
    var barEnergy: [Double]? = nil
}

/// Composes validated patterns into a stage using seeded randomness.
///
/// Rules: entry/exit compatibility, tier-weighted difficulty, no immediate repeats,
/// a mandatory Surfer (ship) section early in every stage (Wave joins from stage 9),
/// a mandatory double-jump section (a pattern proven to need the air jump) right after the
/// Surfer section or from 45% of the stage (Surfer/Wave sections are steered back to Runner
/// from 40% until it has happened), a settle gap after mode transitions so a double-jump obstacle never follows a
/// section where the player cannot have landed and regained both jumps, bar alignment for
/// kick/snare rhythm patterns, music-structure bias (transitions at phrase starts, harder
/// patterns in fills, music-reactive patterns in high-energy bars), and the stage always
/// ends as a normal cube.
/// Mirrors `Tools/dropverse_gen.py` exactly so offline full-stage validation applies.
struct LevelGenerator {
    static let leadInBeats = 4
    static let tailBeats = 2
    static let phraseBeats = 32
    static let transitionWeight = 0.6
    static let doubleBonus = 1.4

    let library: PatternLibrary

    func generate(_ request: StageRequest) -> [(pattern: PatternTemplate, beat: Int)] {
        var rng = SeededGenerator(seed: request.seed)
        var tier = DifficultyTier(stage: request.stage)
        if request.tempoFactor >= 1.25 && tier != .challenging {
            tier = tier.easier // very fast songs already add difficulty
        }
        let weights = tier.patternWeights
        let gap = tier.gapBeats
        // Wave Mode joins the rotation in the Very Hard band (stage 9+), per the difficulty plan.
        let altModes: [MovementMode] = request.stage < 9 ? [.ship] : [.ship, .wave]
        guard let shipReturn = library.pattern(id: "trans.ship_to_cube"),
              let waveReturn = library.pattern(id: "trans.wave_to_cube") else { return [] }
        func returnPattern(_ mode: MovementMode) -> PatternTemplate? {
            switch mode {
            case .ship: return shipReturn
            case .wave: return waveReturn
            case .cube: return nil
            }
        }
        let energy = request.barEnergy
        let median: Double = {
            guard let e = energy, !e.isEmpty else { return 0 }
            return e.sorted()[e.count / 2]
        }()

        var placed: [(pattern: PatternTemplate, beat: Int)] = []
        var recent: [String] = []
        var mode: MovementMode = .cube
        var inModeCount = 0
        var flew = false
        var doubled = false
        var settle = 0
        var beat = Self.leadInBeats
        let total = request.totalBeats

        while true {
            if let last = placed.last {
                beat = max(beat, last.beat + last.pattern.beats + settle)
            }
            let remaining = total - Self.tailBeats - beat
            var candidates: [PatternTemplate] = []
            for p in library.patterns {
                guard p.entry.mode == mode else { continue }
                if p.barAligned == true && beat % 4 != 0 { continue }
                if p.exit.mode == .wave && p.entry.mode != .wave && !altModes.contains(.wave) { continue }
                if weights[p.difficulty] == nil && !p.isTransition { continue }
                let exitMode = p.exit.mode
                let need = p.beats + (exitMode == .cube ? 0 : gap + (returnPattern(exitMode)?.beats ?? 0))
                if need > remaining { continue }
                candidates.append(p)
            }
            if candidates.isEmpty {
                if mode != .cube, let back = returnPattern(mode), back.beats <= total - beat {
                    placed.append((back, beat))
                    beat += back.beats
                    mode = .cube
                }
                break
            }
            if !flew && mode == .cube && Double(beat) >= Double(total) * 0.25 {
                let forced = candidates.filter { altModes.contains($0.exit.mode) }
                if !forced.isEmpty { candidates = forced }
            }
            if !doubled && mode == .cube && (flew || Double(beat) >= Double(total) * 0.45) {
                let forced = candidates.filter { $0.requiredJumps == 2 }
                if !forced.isEmpty { candidates = forced }
            }
            if !doubled && mode != .cube && Double(beat) >= Double(total) * 0.4 {
                let forced = candidates.filter { $0.exit.mode == .cube }
                if !forced.isEmpty { candidates = forced }
            }
            if candidates.count > 1 {
                let lastTwo = recent.suffix(2)
                let fresh = candidates.filter { !lastTwo.contains($0.id) }
                if !fresh.isEmpty { candidates = fresh }
            }
            let bar = beat / 4
            let e: Double = {
                if let energy, bar < energy.count { return energy[bar] }
                return median
            }()
            let phrasePos = beat % Self.phraseBeats
            let lastSix = recent.suffix(6)
            var totalWeight = 0.0
            var ws: [Double] = []
            ws.reserveCapacity(candidates.count)
            for p in candidates {
                var w = weights[p.difficulty] ?? Self.transitionWeight
                if lastSix.contains(p.id) { w *= 0.25 }
                if energy != nil && e > median * 1.1 && p.tags.contains(where: { ["music", "bass", "laser", "eq"].contains($0) }) {
                    w *= 1.5
                }
                if phrasePos < 4 && p.tags.contains("transition") { w *= 2.0 }
                if phrasePos >= 24 && p.difficulty >= 3 { w *= 1.3 }
                if mode != .cube && p.exit.mode == .cube { w *= 0.4 + 0.8 * Double(inModeCount) }
                if p.tags.contains("double") { w *= Self.doubleBonus }
                ws.append(w)
                totalWeight += w
            }
            let r = rng.nextDouble() * totalWeight
            var choice = candidates[candidates.count - 1]
            var acc = 0.0
            for (p, w) in zip(candidates, ws) {
                acc += w
                if r < acc {
                    choice = p
                    break
                }
            }
            placed.append((choice, beat))
            recent.append(choice.id)
            let newMode = choice.exit.mode
            if altModes.contains(newMode) { flew = true }
            if choice.requiredJumps == 2 { doubled = true }
            settle = choice.settleBeats ?? 0
            inModeCount = newMode == mode ? inModeCount + 1 : 0
            mode = newMode
            beat += choice.beats + gap
        }
        return placed
    }

    /// Fixed, gentle sequence for the optional tutorial, each with an on-screen hint.
    static let tutorialSteps: [(id: String, hint: String)] = [
        ("cube.spike_rhythm", "TAP to jump. HOLD to jump higher and keep jumping."),
        ("cube.block_stairs", "Land on blocks. Hitting a block's side is fatal."),
        ("cube.pad_launch", "Yellow pads launch you automatically."),
        ("cube.orb_spike_bed", "TAP while touching an orb for a mid-air jump."),
        ("dj.long_gap", "DOUBLE JUMP: tap again in mid-air. Landing gives you both jumps back."),
        ("dj.kick_snare", "Jump on the kick, double jump on the snare."),
        ("cube.gravity_flip", "Gravity portals flip you to the ceiling."),
        ("trans.cube_to_ship", "SURFER: HOLD to rise, RELEASE to fall."),
        ("ship.corridor", "Fly through the gaps."),
        ("trans.ship_to_cube", "Cube portal: back to running."),
        ("trans.cube_to_wave", "WAVE: HOLD to go up diagonally, RELEASE to go down."),
        ("wave.zigzag", "Weave between the barriers."),
        ("trans.wave_to_cube", "Tutorial complete. Every drop is a new world!"),
    ]
}
