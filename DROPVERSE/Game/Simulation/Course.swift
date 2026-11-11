import Foundation

/// Piecewise-linear mapping from course time (tau) to world x, built from speed changes.
struct SpeedTrack {
    struct Segment {
        var tau: Double
        var x: Double
        var mult: Double
    }

    private(set) var segments: [Segment] = [Segment(tau: -1e6, x: -1e6 * Sim.speed, mult: 1)]

    mutating func add(tau: Double, mult: Double) {
        let last = segments[segments.count - 1]
        precondition(tau >= last.tau, "speed changes must be appended in time order")
        let x = last.x + (tau - last.tau) * Sim.speed * last.mult
        if abs(tau - last.tau) < 1e-12 {
            segments[segments.count - 1] = Segment(tau: last.tau, x: last.x, mult: mult)
        } else {
            segments.append(Segment(tau: tau, x: x, mult: mult))
        }
    }

    func segment(at tau: Double) -> Segment {
        // Segments are few (speed portals are rare): reverse linear scan.
        var i = segments.count - 1
        while i > 0, segments[i].tau > tau { i -= 1 }
        return segments[i]
    }

    func x(at tau: Double) -> Double {
        let s = segment(at: tau)
        return s.x + (tau - s.tau) * Sim.speed * s.mult
    }

    func mult(at tau: Double) -> Double {
        segment(at: tau).mult
    }
}

enum ObjectKind: String, Sendable, CaseIterable {
    case spike, block, noteBlock, pillar, movingBlock, fallingPlatform
    /// Intentional gap in the floor. Simulated through `Course.floorSegments`; this object
    /// exists so the gap is always *drawn* (the v0.2 bug: pits were simulated but invisible).
    case pit
    case hazardBlock, noteHazard, saw, pendulum
    case laser, gate, bassWall
    case pad, orb, portal, speedPortal
}

enum PortalKind: String, Sendable {
    case cube, ship, wave, gravityFlip, gravityNormal, mini, big
}

/// A runtime obstacle placed in world space. Time-dependent geometry is a pure
/// function of course time, so the simulation, renderer and validator agree exactly.
struct CourseObject: Identifiable {
    let id: Int
    let kind: ObjectKind
    /// Course time of the owning pattern's first beat (phase origin).
    let tau0: Double

    // Rect geometry (blocks, hazards, lasers, walls, pads; spikes use x0/y0 as row origin).
    var x0: Double = 0
    var x1: Double = 0
    var y0: Double = 0
    var y1: Double = 0
    // Circle geometry (saw, orb) / pendulum pivot.
    var cx: Double = 0
    var cy: Double = 0
    var radius: Double = 0
    var collisionRadius: Double = 0

    var count = 1
    var downward = false
    var motion: MotionSpec?

    // Timed (laser/gate)
    var period: Double = 1
    var on: Double = 0
    var duration: Double = 0
    var phase: Double = 0
    var horizontal = false
    // Bass wall
    var hMin: Double = 0
    var hMax: Double = 0
    // Pendulum
    var length: Double = 0
    var amplitude: Double = 0
    // Interactives
    var variant: String = ""
    var portal: PortalKind?
    var speedMult: Double = 1
    /// Falling platform release beat (local to the pattern).
    var fallAt: Double?

    func localBeats(_ tau: Double) -> Double { (tau - tau0) / Sim.beatTau }

    static func wave(_ local: Double, period: Double, phase: Double) -> Double {
        sin(2 * Double.pi * (local - phase) / period)
    }

    func offset(_ tau: Double) -> (dx: Double, dy: Double) {
        guard let m = motion else { return (0, 0) }
        let d = m.amp * Self.wave(localBeats(tau), period: m.period, phase: m.phase ?? 0)
        return m.axis == .x ? (d, 0) : (0, d)
    }

    /// Rect at time tau (x0, x1, y0, y1), including motion and falling.
    func rect(_ tau: Double) -> (Double, Double, Double, Double) {
        let o = offset(tau)
        var dy = o.dy
        if let fallAt {
            let lb = localBeats(tau) - fallAt
            if lb > 0 {
                let dt = lb * Sim.beatTau
                dy -= 0.5 * Sim.fallGravity * dt * dt
            }
        }
        return (x0 + o.dx, x1 + o.dx, y0 + dy, y1 + dy)
    }

    /// Beats until a falling platform drops (negative once it has dropped); nil for others.
    func beatsUntilFall(_ tau: Double) -> Double? {
        guard let fallAt else { return nil }
        return fallAt - localBeats(tau)
    }

    func isActive(_ tau: Double) -> Bool {
        var local = (localBeats(tau) - phase).truncatingRemainder(dividingBy: period)
        if local < 0 { local += period }
        return local >= on && local < on + duration
    }

    /// Beats until the next activation (0 when active). Used for charge-up telegraphs.
    func beatsUntilActive(_ tau: Double) -> Double {
        var local = (localBeats(tau) - phase).truncatingRemainder(dividingBy: period)
        if local < 0 { local += period }
        if local >= on && local < on + duration { return 0 }
        return local < on ? on - local : period - local + on
    }

    func bassHeight(_ tau: Double) -> Double {
        let s = 0.5 - 0.5 * cos(2 * Double.pi * (localBeats(tau) - phase) / period)
        return hMin + (hMax - hMin) * s
    }

    func pendulumBall(_ tau: Double) -> (x: Double, y: Double, angle: Double) {
        let a = amplitude * Self.wave(localBeats(tau), period: period, phase: phase)
        return (cx + length * sin(a), cy - length * cos(a), a)
    }

    /// Conservative x-extent including motion, for culling.
    var minX: Double {
        switch kind {
        case .saw, .orb:
            return cx - radius - motionXAmp
        case .pendulum:
            return cx - length - radius
        case .portal, .speedPortal:
            return x0 - 30
        default:
            return x0 - motionXAmp
        }
    }

    var maxX: Double {
        switch kind {
        case .saw, .orb:
            return cx + radius + motionXAmp
        case .pendulum:
            return cx + length + radius
        case .portal, .speedPortal:
            return x0 + 30
        default:
            return x1 + motionXAmp
        }
    }

    private var motionXAmp: Double {
        guard let m = motion, m.axis == .x else { return 0 }
        return abs(m.amp)
    }

    var isSolid: Bool {
        kind == .block || kind == .noteBlock || kind == .pillar || kind == .movingBlock || kind == .fallingPlatform
    }
    var isHazard: Bool {
        switch kind {
        case .spike, .hazardBlock, .noteHazard, .saw, .pendulum, .laser, .gate, .bassWall: return true
        default: return false
        }
    }
    var isTrigger: Bool { kind == .pad || kind == .orb || kind == .portal }
}

/// A placed pattern, kept for HUD/debug and tutorial checkpoints.
struct PlacedPattern {
    /// Unique per run, used to give guide markers stable identities.
    let serial: Int
    let pattern: PatternTemplate
    let stage: Int
    let tauStart: Double
    let tauEnd: Double
    let xStart: Double
}

/// All obstacles of the run, appended stage by stage. Objects are kept sorted by `minX`.
struct Course {
    private(set) var objects: [CourseObject] = []
    private(set) var pits: [(Double, Double)] = []
    private(set) var floorSegments: [(Double, Double)] = [(-1e7, 1e7)]
    private(set) var speed = SpeedTrack()
    private(set) var placed: [PlacedPattern] = []
    private var nextID = 0
    private var nextSerial = 0

    private mutating func makeID() -> Int {
        nextID += 1
        return nextID
    }

    /// Adds a pattern with its first beat at `tau0`. Returns the course time at the pattern's end.
    @discardableResult
    mutating func append(_ pattern: PatternTemplate, at tau0: Double, stage: Int, baseMult: Double = 1) -> Double {
        var changes = (pattern.speed ?? [SpeedChange(at: 0, mult: baseMult)]).sorted { $0.at < $1.at }
        if let first = changes.first, first.at > 0 {
            changes.insert(SpeedChange(at: 0, mult: baseMult), at: 0)
        }
        var newObjects: [CourseObject] = []
        for c in changes {
            let tau = tau0 + c.at * Sim.beatTau
            speed.add(tau: tau, mult: c.mult)
            if c.at > 0 {
                var o = CourseObject(id: makeID(), kind: .speedPortal, tau0: tau0)
                o.x0 = speed.x(at: tau)
                o.speedMult = c.mult
                newObjects.append(o)
            }
        }
        let tauEnd = tau0 + Double(pattern.beats) * Sim.beatTau
        let xStart = speed.x(at: tau0)

        func X(_ b: Double) -> Double { speed.x(at: tau0 + b * Sim.beatTau) }

        for p in pattern.objects {
            switch p.type {
            case "spike":
                var o = CourseObject(id: makeID(), kind: .spike, tau0: tau0)
                o.count = p.count ?? 1
                o.downward = p.dir == "down"
                o.x0 = X(p.x)
                o.x1 = o.x0 + Double(o.count) * Sim.spikeWidth
                o.y0 = Sim.floorY + (p.y ?? 0)
                o.y1 = o.y0
                o.motion = p.move
                newObjects.append(o)
            case "block", "mblock", "fallblock":
                let kind: ObjectKind
                if p.type == "fallblock" {
                    kind = .fallingPlatform
                } else if p.type == "mblock" || p.move != nil {
                    kind = .movingBlock
                } else if p.style == "note" {
                    kind = .noteBlock
                } else if p.style == "pillar" {
                    kind = .pillar
                } else {
                    kind = .block
                }
                var o = CourseObject(id: makeID(), kind: kind, tau0: tau0)
                o.x0 = X(p.x)
                o.x1 = X(p.x + (p.w ?? 1))
                o.y0 = Sim.floorY + (p.y ?? 0)
                o.y1 = o.y0 + (p.h ?? 30)
                o.motion = p.move
                if p.type == "fallblock" { o.fallAt = p.fallAt ?? 2 }
                newObjects.append(o)
            case "pit":
                let gap = (X(p.x), X(p.x + (p.w ?? 1)))
                pits.append(gap)
                var o = CourseObject(id: makeID(), kind: .pit, tau0: tau0)
                o.x0 = gap.0
                o.x1 = gap.1
                o.y0 = -1000
                o.y1 = Sim.floorY
                newObjects.append(o)
            case "hazard", "mhazard", "notehazard":
                var o = CourseObject(id: makeID(), kind: p.type == "notehazard" ? .noteHazard : .hazardBlock, tau0: tau0)
                o.x0 = X(p.x)
                o.x1 = X(p.x + (p.w ?? 0.3))
                o.y0 = Sim.floorY + (p.y ?? 0)
                o.y1 = o.y0 + (p.h ?? 30)
                o.motion = p.move
                newObjects.append(o)
            case "saw":
                var o = CourseObject(id: makeID(), kind: .saw, tau0: tau0)
                o.cx = X(p.x)
                o.cy = Sim.floorY + (p.y ?? 100)
                o.radius = p.r ?? 34
                o.collisionRadius = o.radius * 0.8
                o.motion = p.move
                newObjects.append(o)
            case "pendulum":
                var o = CourseObject(id: makeID(), kind: .pendulum, tau0: tau0)
                o.cx = X(p.x)
                o.cy = Sim.floorY + (p.y ?? 430)
                o.length = p.len ?? 300
                o.radius = p.r ?? 30
                o.collisionRadius = o.radius * 0.85
                o.amplitude = (p.amp ?? 40) * Double.pi / 180
                o.period = p.period ?? 4
                o.phase = p.phase ?? 0
                newObjects.append(o)
            case "laser", "gate":
                var o = CourseObject(id: makeID(), kind: p.type == "gate" ? .gate : .laser, tau0: tau0)
                o.x0 = X(p.x)
                o.x1 = X(p.x + (p.w ?? 0.12))
                o.y0 = Sim.floorY + (p.y ?? 0)
                o.y1 = o.y0 + (p.h ?? 100)
                o.period = p.period ?? 2
                o.on = p.on ?? 0
                o.duration = p.dur ?? 1
                o.phase = p.phase ?? 0
                o.horizontal = p.orientation == "horizontal"
                o.motion = p.move
                newObjects.append(o)
            case "basswall":
                var o = CourseObject(id: makeID(), kind: .bassWall, tau0: tau0)
                o.x0 = X(p.x)
                o.x1 = X(p.x + (p.w ?? 0.3))
                o.y0 = Sim.floorY + (p.y ?? 0)
                o.hMin = p.hmin ?? 0
                o.hMax = p.hmax ?? 80
                o.period = p.period ?? 2
                o.phase = p.phase ?? 0
                newObjects.append(o)
            case "eq":
                let barW = p.barW ?? 0.2
                let gap = p.gap ?? 0.1
                for i in 0..<(p.bars ?? 4) {
                    let bx = p.x + Double(i) * (barW + gap)
                    var o = CourseObject(id: makeID(), kind: .bassWall, tau0: tau0)
                    o.x0 = X(bx)
                    o.x1 = X(bx + barW)
                    o.y0 = Sim.floorY
                    o.hMin = p.hmin ?? 6
                    o.hMax = p.hmax ?? 120
                    o.period = p.period ?? 2
                    o.phase = (p.phase ?? 0) + Double(i) * (p.step ?? 0.25)
                    o.variant = "eq"
                    newObjects.append(o)
                }
            case "pad":
                var o = CourseObject(id: makeID(), kind: .pad, tau0: tau0)
                o.downward = p.dir == "down"
                let base = Sim.floorY + (p.y ?? 0)
                o.x0 = X(p.x)
                o.x1 = o.x0 + 40
                o.y0 = o.downward ? base - 14 : base
                o.y1 = o.downward ? base : base + 14
                o.variant = p.kind ?? "yellow"
                newObjects.append(o)
            case "orb":
                var o = CourseObject(id: makeID(), kind: .orb, tau0: tau0)
                o.cx = X(p.x)
                o.cy = Sim.floorY + (p.y ?? 100)
                o.radius = 30
                o.collisionRadius = 30
                o.variant = p.kind ?? "yellow"
                newObjects.append(o)
            case "portal":
                var o = CourseObject(id: makeID(), kind: .portal, tau0: tau0)
                o.x0 = X(p.x)
                o.x1 = o.x0
                o.portal = PortalKind(rawValue: p.kind ?? "cube")
                newObjects.append(o)
            default:
                continue // rejected earlier by PatternLibrary.validateStructure
            }
        }

        if speed.mult(at: tauEnd - 1e-9) != baseMult {
            speed.add(tau: tauEnd, mult: baseMult)
            var o = CourseObject(id: makeID(), kind: .speedPortal, tau0: tau0)
            o.x0 = speed.x(at: tauEnd)
            o.speedMult = baseMult
            newObjects.append(o)
        }

        objects.append(contentsOf: newObjects)
        objects.sort { $0.minX < $1.minX }
        rebuildFloor()
        nextSerial += 1
        placed.append(PlacedPattern(serial: nextSerial, pattern: pattern, stage: stage, tauStart: tau0, tauEnd: tauEnd, xStart: xStart))
        return tauEnd
    }

    /// Records the stage's base speed at its start so speed portals never leak across stages.
    mutating func beginStage(at tau: Double) {
        if speed.mult(at: tau) != 1 { speed.add(tau: tau, mult: 1) }
    }

    /// Drops objects far behind the player to keep per-step scans short.
    mutating func discard(before x: Double) {
        objects.removeAll { $0.maxX < x }
        pits.removeAll { $0.1 < x }
        placed.removeAll { $0.xStart < x - 4000 }
        rebuildFloor()
    }

    /// Index of the first object whose minX could reach `x` (objects are sorted by minX).
    func firstIndex(minXAtLeast x: Double) -> Int {
        var lo = 0
        var hi = objects.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if objects[mid].minX < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private mutating func rebuildFloor() {
        let sorted = pits.sorted { $0.0 < $1.0 }
        var segments: [(Double, Double)] = []
        var cursor = -1e7
        for (a, b) in sorted {
            if a > cursor { segments.append((cursor, a)) }
            cursor = max(cursor, b)
        }
        segments.append((cursor, 1e7))
        floorSegments = segments
    }

    /// The longest object width in the course, used as a scan window for culling.
    static let maxObjectSpan: Double = 1600
}
