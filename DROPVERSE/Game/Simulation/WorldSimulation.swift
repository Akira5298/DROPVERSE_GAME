import Foundation

/// Player state in reference units. Value type: the validator copies it freely.
struct PlayerState: Hashable {
    var y: Double
    var vy: Double = 0
    var mode: MovementMode
    /// +1 = normal gravity (falls toward the floor), -1 = flipped (falls toward the ceiling).
    var gravitySign: Double
    var mini: Bool
    var grounded: Bool
    var timeSinceGrounded: Double = 0
    var timeSincePress: Double = .infinity
    var holdElapsed: Double = 0
    var holdActive = false
    var dead = false
    var deathCause: DeathCause = .none
    var usedTriggers: Set<Int> = []
    /// Jumps left before the next valid landing (Runner mode only).
    var jumpsRemaining: Int
    /// 2 in the game; the validator lowers it to 1 to prove a pattern needs the air jump.
    var maxJumps: Int

    // Diagnostics only (never read by the physics).
    var supportID: Int = Int.min
    var supportCount = 0
    var lastContact: String = ""

    enum DeathCause: String, Hashable { case none, wall, head, crushed, hazard, fell }

    /// Support identifiers for diagnostics.
    static let supportNone = Int.min
    static let supportCeiling = -1
    static func supportFloor(_ index: Int) -> Int { -1000 - index }

    init(mode: MovementMode = .cube, flipped: Bool = false, mini: Bool = false, maxJumps: Int = Sim.maxJumps) {
        self.mode = mode
        self.gravitySign = flipped ? -1 : 1
        self.mini = mini
        let half = mini ? Sim.halfMini : Sim.halfBig
        self.y = flipped ? Sim.ceilingY - half : Sim.floorY + half
        self.grounded = mode == .cube
        self.maxJumps = maxJumps
        self.jumpsRemaining = mode == .cube ? maxJumps : maxJumps - 1
    }

    init(entry: PatternState, maxJumps: Int = Sim.maxJumps) {
        self.init(mode: entry.mode, flipped: entry.isFlipped, mini: entry.isMini, maxJumps: maxJumps)
    }

    var half: Double { mini ? Sim.halfMini : Sim.halfBig }

    var stateKey: String { "\(mode.rawValue)|\(gravitySign < 0)|\(mini)" }
}

/// Events from one simulation step, consumed by rendering, audio and expressions.
struct StepEvents: OptionSet {
    let rawValue: UInt16
    static let jumped = StepEvents(rawValue: 1 << 0)
    static let landed = StepEvents(rawValue: 1 << 1)
    static let pad = StepEvents(rawValue: 1 << 2)
    static let orb = StepEvents(rawValue: 1 << 3)
    static let portal = StepEvents(rawValue: 1 << 4)
    static let gravityChanged = StepEvents(rawValue: 1 << 5)
    static let modeChanged = StepEvents(rawValue: 1 << 6)
    static let sizeChanged = StepEvents(rawValue: 1 << 7)
    static let died = StepEvents(rawValue: 1 << 8)
    static let doubleJumped = StepEvents(rawValue: 1 << 9)
    static let ledgeCaught = StepEvents(rawValue: 1 << 10)
    /// Left the ground without jumping, a pad, an orb or a portal (walked off a ledge, or the
    /// support moved away). Logged by the flight recorder as a possible "unexpected fall".
    static let lostSupport = StepEvents(rawValue: 1 << 11)
}

private enum ContactSide { case top, bottom, side }

/// Deterministic gameplay simulation. Mirrors `Tools/dropverse_sim.py::step`.
enum WorldPhysics {
    static func overlap(_ px: Double, _ py: Double, _ h: Double, _ r: (Double, Double, Double, Double)) -> Bool {
        px + h > r.0 && px - h < r.1 && py + h > r.2 && py - h < r.3
    }

    static func circleHit(_ px: Double, _ py: Double, _ h: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Bool {
        let nx = min(max(cx, px - h), px + h)
        let ny = min(max(cy, py - h), py + h)
        let dx = nx - cx
        let dy = ny - cy
        return dx * dx + dy * dy < r * r
    }

    static func hazardHit(_ o: CourseObject, _ tau: Double, _ px: Double, _ py: Double, _ h: Double) -> Bool {
        switch o.kind {
        case .spike:
            let off = o.offset(tau)
            for i in 0..<o.count {
                let cx = o.x0 + Sim.spikeWidth / 2 + Double(i) * Sim.spikeWidth + off.dx
                let base = o.y0 + off.dy
                let y0 = o.downward ? base - Sim.spikeCoreHeight : base
                let y1 = o.downward ? base : base + Sim.spikeCoreHeight
                if overlap(px, py, h, (cx - Sim.spikeCoreHalf, cx + Sim.spikeCoreHalf, y0, y1)) { return true }
            }
            return false
        case .hazardBlock, .noteHazard:
            return overlap(px, py, h, o.rect(tau))
        case .saw:
            let off = o.offset(tau)
            return circleHit(px, py, h, o.cx + off.dx, o.cy + off.dy, o.collisionRadius)
        case .pendulum:
            let b = o.pendulumBall(tau)
            return circleHit(px, py, h, b.x, b.y, o.collisionRadius)
        case .laser, .gate:
            return o.isActive(tau) && overlap(px, py, h, o.rect(tau))
        case .bassWall:
            return overlap(px, py, h, (o.x0, o.x1, o.y0, o.y0 + o.bassHeight(tau)))
        default:
            return false
        }
    }

    /// Floor segments, the ceiling and every solid near `x`, with their previous-step rects.
    private static func solids(course: Course, x: Double, tau: Double, tauPrev: Double, start: Int)
        -> [(id: Int, rect: (Double, Double, Double, Double), prev: (Double, Double, Double, Double))] {
        var out: [(id: Int, rect: (Double, Double, Double, Double), prev: (Double, Double, Double, Double))] = []
        out.reserveCapacity(8)
        for (index, seg) in course.floorSegments.enumerated() where seg.1 >= x - 80 && seg.0 <= x + 80 {
            let r = (seg.0, seg.1, -1000.0, Sim.floorY)
            out.append((PlayerState.supportFloor(index), r, r))
        }
        let ceiling = (-1e7, 1e7, Sim.ceilingY, Sim.ceilingY + 1000)
        out.append((PlayerState.supportCeiling, ceiling, ceiling))
        var i = start
        while i < course.objects.count {
            let o = course.objects[i]
            if o.minX > x + 80 { break }
            i += 1
            if o.isSolid {
                let r = o.rect(tau)
                if !(r.1 < x - 80 || r.0 > x + 80) {
                    out.append((o.id, r, o.rect(tauPrev)))
                }
            }
        }
        return out
    }

    /// True when the falling player will reach a support within the jump buffer: a tap now is
    /// then a buffered *ground* jump instead of spending the air jump.
    static func landingSoon(course: Course, player p: PlayerState, x: Double, tau: Double, mult: Double, start: Int) -> Bool {
        let gs = p.gravitySign
        guard p.vy * gs < 0 else { return false }
        let h = p.half
        let reach = abs(p.vy) * Sim.buffer + 0.5 * Sim.gravity * Sim.buffer * Sim.buffer
        let xHi = x + h + Sim.speed * mult * Sim.buffer
        let foot = gs > 0 ? p.y - h : p.y + h
        for s in solids(course: course, x: x, tau: tau, tauPrev: tau, start: start) {
            let r = s.rect
            if r.1 < x - h || r.0 > xHi { continue }
            if gs > 0 && r.3 <= foot + 0.5 && foot - r.3 <= reach { return true }
            if gs < 0 && r.2 >= foot - 0.5 && r.2 - foot <= reach { return true }
        }
        return false
    }

    /// True when an unused orb is under the player (a tap then belongs to the orb).
    static func touchingOrb(course: Course, player p: PlayerState, x: Double, start: Int) -> Bool {
        let h = p.half + Sim.triggerPad
        var i = start
        while i < course.objects.count {
            let o = course.objects[i]
            if o.minX > x + 80 { break }
            i += 1
            if o.kind == .orb, !p.usedTriggers.contains(o.id), circleHit(x, p.y, h, o.cx, o.cy, o.collisionRadius) {
                return true
            }
        }
        return false
    }

    /// Advances `p` by one fixed step of `dtau` reference seconds starting at course time `tauPrev`.
    @discardableResult
    static func step(course: Course, player p: inout PlayerState, tauPrev: Double, dtau: Double,
                     held: Bool, pressed: Bool, hazardMargin: Double = 0) -> StepEvents {
        var events: StepEvents = []
        let tau = tauPrev + dtau
        let xPrev = course.speed.x(at: tauPrev)
        let x = course.speed.x(at: tau)
        let mult = course.speed.mult(at: tau)
        let gs = p.gravitySign
        let start = course.firstIndex(minXAtLeast: x - Course.maxObjectSpan)
        if pressed { p.timeSincePress = 0 }

        // 1. Mode physics
        switch p.mode {
        case .cube:
            let canJump = p.grounded || p.timeSinceGrounded <= Sim.coyote
            if !canJump && p.jumpsRemaining >= p.maxJumps {
                p.jumpsRemaining = p.maxJumps - 1 // walked off a ledge: the ground jump is gone
            }
            let fresh = p.timeSincePress <= Sim.buffer
            if canJump && (fresh || held) {
                p.vy = (p.mini ? Sim.jumpMini : Sim.jump) * gs
                p.grounded = false
                p.timeSinceGrounded = .infinity
                p.timeSincePress = .infinity
                p.jumpsRemaining = p.maxJumps - 1
                p.holdActive = true
                p.holdElapsed = 0
                events.insert(.jumped)
            } else if fresh && !canJump && p.jumpsRemaining > 0
                        && !touchingOrb(course: course, player: p, x: xPrev, start: start)
                        && !landingSoon(course: course, player: p, x: xPrev, tau: tauPrev, mult: mult, start: start) {
                // Air jump: a new tap only (holding never triggers it); velocity is reset.
                p.vy = (p.mini ? Sim.jump2Mini : Sim.jump2) * gs
                p.jumpsRemaining -= 1
                p.timeSincePress = .infinity
                p.holdActive = true
                p.holdElapsed = 0
                events.insert(.doubleJumped)
            }
            if p.holdActive {
                if held && p.holdElapsed < Sim.holdMax && p.vy * gs > 0 {
                    p.holdElapsed += dtau
                } else {
                    p.holdActive = false
                }
            }
            let g = Sim.gravity * (p.holdActive ? Sim.holdScale : 1)
            p.vy -= g * gs * dtau
            p.vy = gs > 0 ? max(p.vy, -Sim.terminal) : min(p.vy, Sim.terminal)
        case .ship:
            let acc = held ? (Sim.shipThrust - Sim.shipGravity) : -Sim.shipGravity
            p.vy += acc * gs * dtau
            p.vy = max(-Sim.shipMax, min(Sim.shipMax, p.vy))
        case .wave:
            let slope = p.mini ? Sim.waveSlopeMini : Sim.waveSlope
            p.vy = (held ? 1 : -1) * gs * Sim.speed * mult * slope
        }

        let yPrev = p.y
        p.y += p.vy * dtau
        var h = p.half
        let wasGrounded = p.grounded
        p.grounded = false
        p.supportCount = 0
        p.supportID = PlayerState.supportNone

        // 2. Solids: floor segments, ceiling, blocks.
        let solidList = solids(course: course, x: x, tau: tau, tauPrev: tauPrev, start: start)
        for s in solidList {
            let r = s.rect
            guard overlap(x, p.y, h, r) else { continue }
            let rp = s.prev
            let prevBottom = yPrev - h
            let prevTop = yPrev + h
            let side: ContactSide
            var caught = false
            if prevBottom >= rp.3 - Sim.landTolerance {
                side = .top
            } else if prevTop <= rp.2 + Sim.landTolerance {
                side = .bottom
            } else if prevBottom >= rp.3 - Sim.edgeSnap && (p.mode != .cube || (gs > 0 && p.vy <= 0)) {
                // Ledge catch: last step the player was at most edgeSnap below this surface.
                side = .top
                caught = true
            } else if prevTop <= rp.2 + Sim.edgeSnap && (p.mode != .cube || (gs < 0 && p.vy >= 0)) {
                side = .bottom
                caught = true
            } else {
                side = .side
            }
            if side == .side {
                p.dead = true
                p.deathCause = .wall
                p.lastContact = "side hit #\(s.id)"
                return events.union(.died)
            }
            if caught { events.insert(.ledgeCaught) }
            if p.mode == .cube {
                if (side == .top && gs > 0) || (side == .bottom && gs < 0) {
                    p.y = side == .top ? r.3 + h : r.2 - h
                    p.vy = 0
                    p.grounded = true
                    p.jumpsRemaining = p.maxJumps
                    p.supportCount += 1
                    p.supportID = s.id
                } else {
                    p.dead = true
                    p.deathCause = .head
                    p.lastContact = "head hit #\(s.id)"
                    return events.union(.died)
                }
            } else {
                if side == .top {
                    p.y = r.3 + h
                    p.vy = max(p.vy, 0)
                } else {
                    p.y = r.2 - h
                    p.vy = min(p.vy, 0)
                }
                if p.mode == .ship && ((side == .top && gs > 0) || (side == .bottom && gs < 0)) {
                    p.grounded = true
                    p.supportCount += 1
                    p.supportID = s.id
                }
            }
        }
        for s in solidList where overlap(x, p.y, h - 0.5, s.rect) {
            p.dead = true
            p.deathCause = .crushed
            p.lastContact = "crushed by #\(s.id)"
            return events.union(.died)
        }

        if p.grounded && !wasGrounded {
            events.insert(.landed)
            p.lastContact = "landed on #\(p.supportID)"
        }
        if wasGrounded && !p.grounded && p.mode == .cube && !events.contains(.jumped) {
            events.insert(.lostSupport)
        }
        if p.grounded {
            p.timeSinceGrounded = 0
        } else if p.timeSinceGrounded != .infinity {
            p.timeSinceGrounded += dtau
        }

        // 3. Triggers
        var i = start
        while i < course.objects.count {
            let o = course.objects[i]
            if o.minX > x + 80 { break }
            i += 1
            switch o.kind {
            case .portal:
                if xPrev < o.x0 && o.x0 <= x, let kind = o.portal {
                    events.formUnion(applyPortal(&p, kind))
                    events.insert(.portal)
                    p.lastContact = "portal \(kind.rawValue)"
                    h = p.half
                }
            case .pad:
                guard p.mode == .cube, !p.usedTriggers.contains(o.id) else { continue }
                if overlap(x, p.y, h + Sim.triggerPad, (o.x0, o.x1, o.y0, o.y1)) {
                    p.vy = (o.variant == "pink" ? Sim.padPink : Sim.padYellow) * p.gravitySign
                    p.grounded = false
                    p.timeSinceGrounded = .infinity
                    p.jumpsRemaining = min(p.jumpsRemaining, p.maxJumps - 1)
                    p.holdActive = false
                    p.usedTriggers.insert(o.id)
                    events.insert(.pad)
                    p.lastContact = "pad #\(o.id)"
                }
            case .orb:
                guard p.mode == .cube, !p.usedTriggers.contains(o.id), p.timeSincePress <= Sim.buffer else { continue }
                if circleHit(x, p.y, h + Sim.triggerPad, o.cx, o.cy, o.collisionRadius) {
                    if o.variant == "gravity" {
                        p.gravitySign = -p.gravitySign
                        p.vy = -p.gravitySign * Sim.orbGravityPush
                        p.jumpsRemaining = min(p.jumpsRemaining, p.maxJumps - 1)
                        events.insert(.gravityChanged)
                    } else {
                        p.vy = (o.variant == "pink" ? Sim.orbPink : Sim.orbYellow) * p.gravitySign
                    }
                    p.grounded = false
                    p.timeSinceGrounded = .infinity
                    p.timeSincePress = .infinity
                    p.holdActive = false
                    p.usedTriggers.insert(o.id)
                    events.insert(.orb)
                    p.lastContact = "orb #\(o.id)"
                }
            default:
                continue
            }
        }
        if events.contains(.pad) || events.contains(.orb) || events.contains(.portal) { events.remove(.lostSupport) }
        p.timeSincePress += dtau

        // 4. Hazards
        let hh = h + hazardMargin
        i = start
        while i < course.objects.count {
            let o = course.objects[i]
            if o.minX > x + hh { break }
            i += 1
            guard o.isHazard, o.maxX >= x - hh else { continue }
            if hazardHit(o, tau, x, p.y, hh) {
                p.dead = true
                p.deathCause = .hazard
                p.lastContact = "hazard \(o.kind.rawValue) #\(o.id)"
                return events.union(.died)
            }
        }

        // 5. Bounds
        if p.y < Sim.floorY - Sim.killMargin || p.y > Sim.ceilingY + Sim.killMargin {
            p.dead = true
            p.deathCause = .fell
            p.lastContact = "fell out of the playfield"
            return events.union(.died)
        }
        return events
    }

    static func applyPortal(_ p: inout PlayerState, _ kind: PortalKind) -> StepEvents {
        switch kind {
        case .cube, .ship, .wave:
            let mode: MovementMode = kind == .cube ? .cube : (kind == .ship ? .ship : .wave)
            guard p.mode != mode else { return [] }
            p.mode = mode
            p.grounded = false
            p.holdActive = false
            p.timeSinceGrounded = .infinity
            if mode == .ship {
                p.vy *= 0.5
            } else if mode == .cube {
                p.vy = max(-400, min(400, p.vy))
                p.jumpsRemaining = p.maxJumps - 1 // airborne entry: air jump only
            }
            return .modeChanged
        case .gravityFlip:
            guard p.gravitySign > 0 else { return [] }
            p.gravitySign = -1
            p.vy *= 0.5
            p.grounded = false
            p.timeSinceGrounded = .infinity
            p.jumpsRemaining = min(p.jumpsRemaining, p.maxJumps - 1)
            return .gravityChanged
        case .gravityNormal:
            guard p.gravitySign < 0 else { return [] }
            p.gravitySign = 1
            p.vy *= 0.5
            p.grounded = false
            p.timeSinceGrounded = .infinity
            p.jumpsRemaining = min(p.jumpsRemaining, p.maxJumps - 1)
            return .gravityChanged
        case .mini:
            guard !p.mini else { return [] }
            p.mini = true
            return .sizeChanged
        case .big:
            guard p.mini else { return [] }
            p.mini = false
            return .sizeChanged
        }
    }
}
