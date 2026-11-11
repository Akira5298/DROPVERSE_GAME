import Foundation

/// Playability checks for patterns and generated stages.
///
/// Two layers:
/// 1. `structuralIssues` — cheap rule checks (entry/exit chaining, gaps, bounds, corridor
///    widths, lead-in) run on every generated stage at runtime.
/// 2. `solve` — a depth-first solver that searches hold/release inputs (one decision every
///    `decision` reference seconds, so no frame-perfect inputs) through the real simulation
///    with a slightly enlarged hitbox. A found path is a genuine completion. This is used by
///    the unit tests and the offline tool; it is too slow to run every stage on device.
enum LevelValidator {
    struct Issue: CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    // MARK: - Structural checks

    static func structuralIssues(placed: [(pattern: PatternTemplate, beat: Int)], totalBeats: Int) -> [Issue] {
        var issues: [Issue] = []
        var state = PatternState.base.key
        var previousEnd = 0
        for (index, entry) in placed.enumerated() {
            let p = entry.pattern
            if p.entry.key != state {
                issues.append(Issue(message: "\(p.id) entered in state \(state), needs \(p.entry.key)"))
            }
            let minGap = index == 0 ? LevelGenerator.leadInBeats : 1
            if entry.beat - previousEnd < minGap {
                issues.append(Issue(message: "\(p.id) starts \(entry.beat - previousEnd) beats after the previous pattern"))
            }
            previousEnd = entry.beat + p.beats
            state = p.exit.key
        }
        if previousEnd > totalBeats {
            issues.append(Issue(message: "stage overruns its \(totalBeats) beats"))
        }
        if state != PatternState.base.key {
            issues.append(Issue(message: "stage ends in state \(state) instead of a normal cube"))
        }
        return issues
    }

    /// Per-pattern geometric checks that need no simulation.
    static func templateIssues(_ p: PatternTemplate) -> [Issue] {
        var issues: [Issue] = []
        // Nothing standable may sit above what a double jump (or yellow pad + air jump) can reach.
        let maxJumpReach = Reachability.big.doubleMaxHeight + 200
        for o in p.objects {
            if let y = o.y, let h = o.h, (o.type == "block" || o.type == "mblock"), p.entry.mode == .cube, p.exit.mode == .cube,
               y > maxJumpReach, y + h < Sim.playHeight {
                issues.append(Issue(message: "\(p.id): platform at y=\(y) is above the reachable height"))
            }
            if o.type == "saw", let r = o.r, r > 60 {
                issues.append(Issue(message: "\(p.id): saw radius \(r) too large"))
            }
        }
        // Flight corridors must leave at least 2.5x the player's height.
        if p.entry.mode != .cube {
            let floorBlocks = p.objects.filter { ($0.type == "block") && ($0.y ?? 0) <= 0 }
            let ceilBlocks = p.objects.filter { ($0.type == "block") && (($0.y ?? 0) + ($0.h ?? 0)) >= Sim.playHeight }
            for f in floorBlocks {
                for c in ceilBlocks where c.x < f.x + (f.w ?? 1) && f.x < c.x + (c.w ?? 1) {
                    let gap = (c.y ?? 0) - (f.h ?? 0)
                    if gap < Sim.halfBig * 2 * 2.5 {
                        issues.append(Issue(message: "\(p.id): corridor only \(Int(gap)) pt high"))
                    }
                }
            }
        }
        // Bare gaps (no platform inside) must be crossable by a double jump.
        if p.entry.mode == .cube {
            for gap in p.objects where gap.type == "pit" {
                let a = gap.x, b = gap.x + (gap.w ?? 1)
                let hasSupport = p.objects.contains { o in
                    ["block", "mblock", "fallblock"].contains(o.type) && o.x < b && o.x + (o.w ?? 1) > a
                } || p.objects.contains { $0.type == "orb" || $0.type == "pad" }
                if !hasSupport && (b - a) * Sim.beatX > Reachability.big.doubleGapLimit {
                    issues.append(Issue(message: "\(p.id): gap of \(Int((b - a) * Sim.beatX)) pt exceeds double-jump reach"))
                }
            }
        }
        if let first = p.objects.map(\.x).min(), first < 0.5 {
            issues.append(Issue(message: "\(p.id): first object closer than half a beat to the entry"))
        }
        return issues
    }

    // MARK: - Solver

    private struct VisitKey: Hashable {
        let depth: Int
        let y: Int
        let vy: Int
        let state: String
        let held: Bool
        let grounded: Bool
        let holdActive: Bool
        let used: Set<Int>
        let coyoteExpired: Bool
        let jumps: Int
    }

    /// Searches for a completion of `course` from `player` between `tauStart` and `tauEnd`.
    /// Returns the held flag per decision, or nil when no completion exists at this granularity.
    static func solve(course: Course, player: PlayerState, tauStart: Double, tauEnd: Double, dtau: Double,
                      decision: Double = 0.05, hazardMargin: Double = 1, exitState: PatternState? = .base,
                      maxNodes: Int = 400_000) -> [Bool]? {
        let stepsPerDecision = max(1, Int((decision / dtau).rounded()))
        var visited = Set<VisitKey>()
        var path: [Bool] = []
        var budget = maxNodes

        func dfs(_ p: PlayerState, _ tau: Double, _ heldPrev: Bool, _ depth: Int) -> Bool {
            if tau >= tauEnd {
                if let exitState, p.stateKey != exitState.key { return false }
                return true
            }
            let key = VisitKey(depth: depth, y: Int((p.y / 2).rounded()), vy: Int((p.vy / 25).rounded()),
                               state: p.stateKey, held: heldPrev, grounded: p.grounded, holdActive: p.holdActive,
                               used: p.usedTriggers, coyoteExpired: min(p.timeSinceGrounded, 1) > Sim.coyote,
                               jumps: p.jumpsRemaining)
            if visited.contains(key) { return false }
            visited.insert(key)
            budget -= 1
            if budget < 0 { return false }
            for held in [heldPrev, !heldPrev] {
                var q = p
                var t = tau
                for i in 0..<stepsPerDecision {
                    WorldPhysics.step(course: course, player: &q, tauPrev: t, dtau: dtau, held: held,
                                      pressed: held && !heldPrev && i == 0, hazardMargin: hazardMargin)
                    t += dtau
                    if q.dead { break }
                }
                if q.dead { continue }
                path.append(held)
                if dfs(q, t, held, depth + 1) { return true }
                path.removeLast()
            }
            return false
        }

        return dfs(player, tauStart, false, 0) ? path : nil
    }

    /// Builds a course for a generated stage (stage-local time) and proves it with the solver.
    static func proveStage(library: PatternLibrary, placed: [(pattern: PatternTemplate, beat: Int)], totalBeats: Int,
                           tempoFactor: Double, maxNodes: Int = 2_000_000) -> Bool {
        var course = Course()
        for entry in placed {
            course.append(entry.pattern, at: Double(entry.beat) * Sim.beatTau, stage: 0)
        }
        return solve(course: course, player: PlayerState(), tauStart: 0, tauEnd: Double(totalBeats) * Sim.beatTau,
                     dtau: tempoFactor / 120, maxNodes: maxNodes) != nil
    }

    /// Proves a single pattern with the validator's standard lead-in/tail.
    /// `maxJumps: 1` disables the air jump (used to prove a pattern *needs* it).
    static func provePattern(_ p: PatternTemplate, tempoFactor: Double, maxJumps: Int = Sim.maxJumps) -> Bool {
        var course = Course()
        let end = course.append(p, at: 2 * Sim.beatTau, stage: 0)
        return solve(course: course, player: PlayerState(entry: p.entry, maxJumps: maxJumps), tauStart: 0,
                     tauEnd: end + 2 * Sim.beatTau, dtau: tempoFactor / 120, exitState: p.exit) != nil
    }

    // MARK: - Cue verification (Rhythm Timing Guide)

    /// Plays a pattern with scripted presses (beat, holdBeats) — exactly what a player following
    /// the timing guide does — and reports whether it completes in the declared exit state.
    static func runScript(_ pattern: PatternTemplate, presses: [(beat: Double, hold: Double)], tempoFactor k: Double) -> Bool {
        let lead = 2.0
        var course = Course()
        let end = course.append(pattern, at: lead * Sim.beatTau, stage: 0) + 2 * Sim.beatTau
        var p = PlayerState(entry: pattern.entry)
        let dt = k / 120
        let starts = presses.map { (lead + $0.beat) * Sim.beatTau }
        let ends = presses.map { (lead + $0.beat + $0.hold) * Sim.beatTau }
        var done = [Bool](repeating: false, count: presses.count)
        var t = 0.0
        while t < end {
            var press = false
            var held = false
            for i in presses.indices {
                if !done[i] && t >= starts[i] {
                    done[i] = true
                    press = true
                }
                if starts[i] <= t && t < ends[i] { held = true }
            }
            WorldPhysics.step(course: course, player: &p, tauPrev: t, dtau: dt, held: held || press, pressed: press)
            t += dt
            if p.dead { return false }
        }
        return p.stateKey == pattern.exit.key
    }

    /// Every cue's centre timing completes the pattern, and so does shifting any single cue to
    /// either edge of its window, at the given tempo factor.
    static func verifyCues(_ pattern: PatternTemplate, tempoFactor k: Double) -> Bool {
        guard let cues = pattern.cues, !cues.isEmpty else { return true }
        let centre = cues.map { (beat: $0.beat, hold: $0.hold) }
        guard runScript(pattern, presses: centre, tempoFactor: k) else { return false }
        for i in cues.indices {
            for sign in [-1.0, 1.0] {
                var shifted = centre
                shifted[i].beat += sign * cues[i].window
                if !runScript(pattern, presses: shifted, tempoFactor: k) { return false }
            }
        }
        return true
    }
}
