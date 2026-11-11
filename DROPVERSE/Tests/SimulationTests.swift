import XCTest
@testable import Dropverse

// MARK: - Helpers

private let dtau = 1.0 / 120.0

private func course(_ objects: [PatternObject], beats: Int = 12, speed: [SpeedChange]? = nil) -> Course {
    var c = Course()
    let p = PatternTemplate(id: "test", name: "test", difficulty: 1, beats: beats, entry: .base, exit: .base, minReaction: 0.4,
                            tags: [], speed: speed, objects: objects)
    c.append(p, at: 0, stage: 0)
    return c
}

/// Runs a scripted input: `presses` are step indices with tap length in steps; returns events per step.
@discardableResult
private func run(_ c: Course, _ p: inout PlayerState, steps: Int, presses: [Int: Int] = [:], dt: Double = dtau,
                 startTau: Double = 0) -> [StepEvents] {
    var all: [StepEvents] = []
    var tau = startTau
    var heldUntil = -1
    for i in 0..<steps {
        let pressed = presses[i] != nil
        if let len = presses[i] { heldUntil = i + len }
        let ev = WorldPhysics.step(course: c, player: &p, tauPrev: tau, dtau: dt, held: i < heldUntil, pressed: pressed)
        tau += dt
        all.append(ev)
        if p.dead { break }
    }
    return all
}

private func firstIndex(_ events: [StepEvents], _ e: StepEvents) -> Int? { events.firstIndex { $0.contains(e) } }
private func count(_ events: [StepEvents], _ e: StepEvents) -> Int { events.filter { $0.contains(e) }.count }

// MARK: - Basic physics

final class SimulationTests: XCTestCase {
    func testTapJumpMatchesBallistics() {
        let c = Course()
        var p = PlayerState()
        var apex = 0.0
        var tau = 0.0
        var air = 0.0
        for i in 0..<300 {
            let ev = WorldPhysics.step(course: c, player: &p, tauPrev: tau, dtau: dtau, held: i < 1, pressed: i == 0)
            tau += dtau
            apex = max(apex, p.y - p.half - Sim.floorY)
            if !p.grounded { air += dtau }
            if i > 0 && ev.contains(.landed) { break }
        }
        let expected = Sim.jump * Sim.jump / (2 * Sim.gravity)
        XCTAssertEqual(apex, expected, accuracy: expected * 0.05)
        XCTAssertEqual(air, 2 * Sim.jump / Sim.gravity, accuracy: 0.04)
    }

    func testShipClampsVerticalSpeed() {
        let c = Course()
        var p = PlayerState(mode: .ship)
        var tau = 0.0
        for _ in 0..<60 { WorldPhysics.step(course: c, player: &p, tauPrev: tau, dtau: dtau, held: true, pressed: false); tau += dtau }
        XCTAssertLessThanOrEqual(p.vy, Sim.shipMax + 1e-9)
        XCTAssertFalse(p.dead)
    }

    func testWaveMovesAtFortyFiveDegrees() {
        let c = Course()
        var p = PlayerState(mode: .wave)
        p.y = 375
        WorldPhysics.step(course: c, player: &p, tauPrev: 0, dtau: dtau, held: true, pressed: true)
        XCTAssertEqual(p.vy, Sim.speed, accuracy: 1e-9)
        WorldPhysics.step(course: c, player: &p, tauPrev: dtau, dtau: dtau, held: false, pressed: false)
        XCTAssertEqual(p.vy, -Sim.speed, accuracy: 1e-9)
    }

    func testOrbNeedsATap() {
        let c = course([PatternObject(type: "orb", x: 1, y: 20, kind: "yellow")], beats: 4)
        var p = PlayerState()
        let ev = run(c, &p, steps: 240)
        XCTAssertNil(firstIndex(ev, .orb))
    }

    func testTempoFolding() {
        XCTAssertEqual(Sim.foldBPM(87), 174)
        XCTAssertEqual(Sim.foldBPM(200), 100)
        XCTAssertEqual(Sim.tempoFactor(bpm: 128), 1)
    }
}

// MARK: - Double jump

final class DoubleJumpTests: XCTestCase {
    func testFirstJumpIsImmediate() {
        var p = PlayerState()
        let ev = run(Course(), &p, steps: 2, presses: [0: 1])
        XCTAssertTrue(ev[0].contains(.jumped), "the first jump must happen on the step the tap arrives")
        XCTAssertEqual(p.jumpsRemaining, 1)
    }

    func testSecondJumpWhileAscending() {
        var p = PlayerState()
        let ev = run(Course(), &p, steps: 20, presses: [0: 1, 12: 1])
        XCTAssertEqual(firstIndex(ev, .doubleJumped), 12)
        XCTAssertEqual(p.jumpsRemaining, 0)
        XCTAssertEqual(p.vy, Sim.jump2 - Sim.gravity * Sim.holdScale * dtau, accuracy: 30)
    }

    func testSecondJumpWhileDescendingResetsVelocity() {
        var p = PlayerState()
        // Tap jump; at step 60 (~0.5 τ) the cube is falling, well above the ground.
        let ev = run(Course(), &p, steps: 61, presses: [0: 1, 60: 1])
        XCTAssertEqual(firstIndex(ev, .doubleJumped), 60)
        XCTAssertGreaterThan(p.vy, 500, "velocity is reset to the jump impulse, not added to the fall")
        XCTAssertLessThanOrEqual(p.vy, Sim.jump2)
    }

    func testThirdJumpIsRejected() {
        var p = PlayerState()
        let ev = run(Course(), &p, steps: 40, presses: [0: 1, 10: 1, 20: 1])
        XCTAssertEqual(count(ev, .jumped) + count(ev, .doubleJumped), 2)
    }

    func testHoldingOnceNeverDoubleJumps() {
        var p = PlayerState()
        let ev = run(Course(), &p, steps: 70, presses: [0: 70])
        XCTAssertEqual(count(ev, .doubleJumped), 0)
        XCTAssertEqual(count(ev, .jumped), 1)
    }

    func testHoldExtendsSecondJump() {
        func apex(holdSecond: Int) -> Double {
            var p = PlayerState()
            var best = 0.0
            var tau = 0.0
            for i in 0..<240 {
                let held = i < 1 || (i >= 30 && i < 30 + holdSecond)
                WorldPhysics.step(course: Course(), player: &p, tauPrev: tau, dtau: dtau, held: held, pressed: i == 0 || i == 30)
                tau += dtau
                best = max(best, p.y)
            }
            return best
        }
        XCTAssertGreaterThan(apex(holdSecond: 30), apex(holdSecond: 1) + 30)
    }

    func testLandingResetsJumps() {
        var p = PlayerState()
        run(Course(), &p, steps: 200, presses: [0: 1, 10: 1])
        XCTAssertTrue(p.grounded)
        XCTAssertEqual(p.jumpsRemaining, Sim.maxJumps)
        let ev = run(Course(), &p, steps: 20, presses: [0: 1, 10: 1], startTau: 200 * dtau)
        XCTAssertEqual(count(ev, .doubleJumped), 1)
    }

    func testCoyoteTime() {
        // Walk off a ledge (block 0.5..2 beats, 60 pt high) and jump 5 steps later.
        let c = course([PatternObject(type: "block", x: 0.4, w: 1.6, h: 60)])
        var p = PlayerState()
        p.y = Sim.floorY + 60 + p.half
        var tau = 0.6 * Sim.beatTau
        var leftAt: Int?
        var jumpedFromCoyote = false
        for i in 0..<300 {
            let press = leftAt != nil && i == leftAt! + 5
            let ev = WorldPhysics.step(course: c, player: &p, tauPrev: tau, dtau: dtau, held: press, pressed: press)
            tau += dtau
            if leftAt == nil && ev.contains(.lostSupport) { leftAt = i }
            if press { jumpedFromCoyote = ev.contains(.jumped) }
            if press { break }
        }
        XCTAssertNotNil(leftAt)
        XCTAssertTrue(jumpedFromCoyote, "a ground jump is still allowed within the coyote window")
        XCTAssertEqual(p.jumpsRemaining, 1)
    }

    func testWalkingOffLedgeLeavesOnlyTheAirJump() {
        let c = course([PatternObject(type: "block", x: 0.4, w: 1.6, h: 60)])
        var p = PlayerState()
        p.y = Sim.floorY + 60 + p.half
        var tau = 0.6 * Sim.beatTau
        var left = false
        for _ in 0..<300 {
            let ev = WorldPhysics.step(course: c, player: &p, tauPrev: tau, dtau: dtau, held: false, pressed: false)
            tau += dtau
            if ev.contains(.lostSupport) { left = true }
            if left && p.timeSinceGrounded > Sim.coyote + dtau { break }
        }
        XCTAssertEqual(p.jumpsRemaining, 1)
    }

    func testJumpBufferBeforeLandingIsAGroundJump() {
        var p = PlayerState()
        run(Course(), &p, steps: 1, presses: [0: 1])
        var tau = dtau
        var press = false
        var sawDouble = false
        var groundJumpAfterLanding = false
        for _ in 0..<200 {
            var pressed = false
            if !press && p.vy < 0 && p.y - p.half - Sim.floorY < 14 {
                pressed = true
                press = true
            }
            let ev = WorldPhysics.step(course: Course(), player: &p, tauPrev: tau, dtau: dtau, held: pressed, pressed: pressed)
            tau += dtau
            if ev.contains(.doubleJumped) { sawDouble = true }
            if press && ev.contains(.jumped) { groundJumpAfterLanding = true; break }
        }
        XCTAssertFalse(sawDouble, "a tap just before landing must not burn the air jump")
        XCTAssertTrue(groundJumpAfterLanding)
    }

    func testSurferAndWaveHaveNoDoubleJump() {
        for mode in [MovementMode.ship, .wave] {
            var p = PlayerState(mode: mode)
            p.y = 375
            let ev = run(Course(), &p, steps: 30, presses: [0: 1, 5: 1, 10: 1])
            XCTAssertEqual(count(ev, .doubleJumped) + count(ev, .jumped), 0)
        }
    }

    func testDoubleJumpRelativeToFlippedGravity() {
        var p = PlayerState(flipped: true)
        let ev = run(Course(), &p, steps: 20, presses: [0: 1, 10: 1])
        XCTAssertNotNil(firstIndex(ev, .doubleJumped))
        XCTAssertLessThan(p.vy, 0, "flipped gravity: jumps go downward")
    }

    func testMiniDoubleJumpIsWeaker() {
        var p = PlayerState(mini: true)
        run(Course(), &p, steps: 11, presses: [0: 1, 10: 1])
        XCTAssertLessThanOrEqual(p.vy, Sim.jump2Mini)
        XCTAssertGreaterThan(p.vy, 400)
    }

    func testPortalIntoRunnerGivesOnlyTheAirJump() {
        let c = course([PatternObject(type: "portal", x: 0.5, kind: "cube")])
        var p = PlayerState(mode: .ship)
        p.y = 400
        run(c, &p, steps: 40)
        XCTAssertEqual(p.mode, .cube)
        XCTAssertLessThanOrEqual(p.jumpsRemaining, 1, "no extra jumps after a portal")
    }

    func testPauseDoesNotTouchJumpState() {
        // Pausing stops the clock; the simulation only changes on steps, so state is preserved.
        var p = PlayerState()
        run(Course(), &p, steps: 12, presses: [0: 1, 10: 1])
        let snapshot = p
        var now: TimeInterval = 5
        let clock = MonotonicGameClock(timeSource: { now })
        clock.start()
        clock.pause()
        now = 50
        XCTAssertEqual(clock.currentTime, 0)
        XCTAssertEqual(p, snapshot)
        XCTAssertEqual(p.jumpsRemaining, 0)
    }

    func testReachabilityMatchesReferenceModel() {
        // Values printed by Tools/dropverse_sim.py::reachability.
        let r = Reachability.big
        XCTAssertEqual(r.singleMaxHeight, 156.1, accuracy: 4)
        XCTAssertEqual(r.singleMaxDistance, 269.3, accuracy: 8)
        XCTAssertEqual(r.doubleMaxHeight, 325.5, accuracy: 8)
        XCTAssertEqual(r.doubleMaxDistance, 541.3, accuracy: 12)
        XCTAssertGreaterThan(r.doubleGapLimit, r.singleGapLimit + 200)
    }
}

// MARK: - Ground continuity & the "unexpected fall" regression

final class GroundContinuityTests: XCTestCase {
    func testFlatGroundForThirtySecondsNeverDropsTheCube() {
        var c = Course()
        var p = PlayerState()
        var tau = 0.0
        for _ in 0..<(120 * 30) {
            let ev = WorldPhysics.step(course: c, player: &p, tauPrev: tau, dtau: dtau, held: false, pressed: false)
            tau += dtau
            XCTAssertFalse(ev.contains(.lostSupport))
            XCTAssertTrue(p.grounded)
            XCTAssertEqual(p.y, Sim.floorY + p.half, accuracy: 1e-6)
        }
        c.discard(before: 1000)
        XCTAssertEqual(c.floorSegments.count, 1)
    }

    func testRunningPastNonIntersectingSpikes() {
        // Ceiling spikes high above the runner: no contact, no fall, no death.
        let c = course([PatternObject(type: "spike", x: 1, y: 450, count: 6, dir: "down")])
        var p = PlayerState()
        let ev = run(c, &p, steps: 600)
        XCTAssertFalse(p.dead)
        XCTAssertEqual(count(ev, .lostSupport), 0)
    }

    func testJumpBeforeAndLandJustAfterAnObstacle() {
        let c = course([PatternObject(type: "spike", x: 2, count: 1)])
        var p = PlayerState()
        // Spike centre crosses at beat 2.147; tap ~0.25 τ earlier.
        let pressStep = Int(((2.0 + 0.147) * Sim.beatTau - 0.26) / dtau)
        let ev = run(c, &p, steps: 900, presses: [pressStep: 1])
        XCTAssertFalse(p.dead)
        XCTAssertNotNil(firstIndex(ev, .landed))
    }

    func testAdjacentAndOverlappingPitsLeaveNoSeams() {
        // Two touching pits, then an overlapping one: floor segments must merge exactly.
        let c = course([PatternObject(type: "pit", x: 2, w: 1), PatternObject(type: "pit", x: 3, w: 1),
                        PatternObject(type: "pit", x: 3.5, w: 1)])
        XCTAssertEqual(c.floorSegments.count, 2)
        XCTAssertEqual(c.floorSegments[0].1, 2 * Sim.beatX, accuracy: 1e-6)
        XCTAssertEqual(c.floorSegments[1].0, 4.5 * Sim.beatX, accuracy: 1e-6)
    }

    func testEveryPitIsDrawn() {
        // Regression for the v0.2 "invisible gap" bug: pits were simulated but never rendered.
        let c = course([PatternObject(type: "pit", x: 2, w: 2.6)])
        let pits = c.objects.filter { $0.kind == .pit }
        XCTAssertEqual(pits.count, 1)
        XCTAssertEqual(pits[0].x0, c.floorSegments[0].1, accuracy: 1e-6)
        XCTAssertEqual(pits[0].x1, c.floorSegments[1].0, accuracy: 1e-6)
        for kind in ObjectKind.allCases {
            XCTAssertTrue(ObstacleRenderer.draws(kind), "\(kind) is simulated but has no visual")
        }
    }

    func testLedgeCatchInsteadOfInvisibleWallDeath() {
        // Reproduction of a reported fall: a running tap jump over a ~230 pt gap meets the far
        // edge a few points low. v0.2 called that a wall hit (death beside apparently solid floor).
        // Within edgeSnap it is now a ledge catch; deeper hits are still (correctly) fatal.
        func attempt(pitWidth: Double) -> PlayerState {
            var c = Course()
            let beats = pitWidth / Sim.beatX
            let p0 = PatternTemplate(id: "gap", name: "gap", difficulty: 1, beats: 8, entry: .base, exit: .base, minReaction: 0.4,
                                     tags: [], speed: nil, objects: [PatternObject(type: "pit", x: 2, w: beats)])
            c.append(p0, at: 0, stage: 0)
            var p = PlayerState(maxJumps: 1)
            let pressStep = Int((2 * Sim.beatX - 10) / Sim.speed / dtau)
            run(c, &p, steps: 600, presses: [pressStep: 1])
            return p
        }
        // 229–231 pt died in v0.2 (measured with Tools/dropverse_sim.py); now they are caught.
        let caught = (229...231).map { attempt(pitWidth: Double($0)) }
        XCTAssertTrue(caught.allSatisfy { !$0.dead }, "short-landing jumps within edgeSnap must be caught")
        let deep = attempt(pitWidth: 300)
        XCTAssertTrue(deep.dead, "missing a wide gap by far is still a real fall")
    }

    func testMovingPlatformCarriesThePlayer() {
        let c = course([PatternObject(type: "pit", x: 1, w: 4),
                        PatternObject(type: "mblock", x: 0.8, w: 3, y: 30, h: 20, move: MotionSpec(axis: .y, amp: 30, period: 2, phase: 0))])
        var p = PlayerState()
        p.y = Sim.floorY + 50 + p.half
        let ev = run(c, &p, steps: Int(2 * Sim.beatTau / dtau), startTau: Sim.beatTau)
        XCTAssertFalse(p.dead)
        XCTAssertGreaterThan(count(ev, .landed) + (p.grounded ? 1 : 0), 0)
    }

    func testFastSpeedAndLowFrameRateStillCollide() {
        // 1.35× speed portal and the largest per-step dτ (k = 1.41): spikes are still hit.
        let c = course([PatternObject(type: "spike", x: 3, count: 1)], speed: [SpeedChange(at: 0.5, mult: 1.35)])
        var p = PlayerState()
        run(c, &p, steps: 600, dt: 1.41 / 120)
        XCTAssertTrue(p.dead)
        XCTAssertEqual(p.deathCause, .hazard)
    }

    func testPlatformAndObstacleAtOnce() {
        // Standing on a block whose top carries a spike further along: death comes from the spike, not the block.
        let c = course([PatternObject(type: "block", x: 0.3, w: 3, h: 40), PatternObject(type: "spike", x: 2, y: 40, count: 1)])
        var p = PlayerState()
        p.y = Sim.floorY + 40 + p.half
        run(c, &p, steps: 600, startTau: 0.4 * Sim.beatTau)
        XCTAssertTrue(p.dead)
        XCTAssertEqual(p.deathCause, .hazard)
    }

    func testStageBoundaryKeepsTheFloorContinuous() {
        var c = Course()
        let empty = PatternTemplate(id: "e", name: "e", difficulty: 1, beats: 8, entry: .base, exit: .base, minReaction: 0.4,
                                    tags: [], speed: nil, objects: [])
        c.append(empty, at: 0, stage: 1)
        c.beginStage(at: 8 * Sim.beatTau)
        c.append(empty, at: 8 * Sim.beatTau, stage: 2)
        var p = PlayerState()
        let ev = run(c, &p, steps: Int(16 * Sim.beatTau / dtau))
        XCTAssertEqual(count(ev, .lostSupport), 0)
        XCTAssertFalse(p.dead)
    }

    func testRepeatedGenerateAndDiscard() throws {
        let lib = try PatternLibrary.loadBundled()
        var c = Course()
        var tau = 0.0
        for (i, p) in lib.patterns.enumerated() where p.entry.mode == .cube && p.exit.mode == .cube {
            tau = c.append(p, at: tau + Sim.beatTau, stage: i)
            c.discard(before: c.speed.x(at: tau) - 3000)
            // Floor segments must stay sorted, non-overlapping and only split at real pits.
            for (a, b) in zip(c.floorSegments, c.floorSegments.dropFirst()) {
                XCTAssertLessThan(a.1, b.0 + 1e-9)
                XCTAssertTrue(c.objects.contains { $0.kind == .pit && abs($0.x0 - a.1) < 1e-6 } || a.1 < c.speed.x(at: tau) - 3000)
            }
        }
    }

    func testGravityInversionMiniAndModeTransitions() {
        let c = course([PatternObject(type: "portal", x: 0.5, kind: "gravityFlip"),
                        PatternObject(type: "portal", x: 3, kind: "gravityNormal"),
                        PatternObject(type: "portal", x: 4.5, kind: "mini"),
                        PatternObject(type: "portal", x: 6, kind: "ship"),
                        PatternObject(type: "portal", x: 7.5, kind: "wave"),
                        PatternObject(type: "portal", x: 9, kind: "cube"),
                        PatternObject(type: "portal", x: 9.5, kind: "big")], beats: 14)
        var p = PlayerState()
        let ev = run(c, &p, steps: Int(13 * Sim.beatTau / dtau))
        XCTAssertFalse(p.dead)
        XCTAssertEqual(p.mode, .cube)
        XCTAssertFalse(p.mini)
        XCTAssertEqual(p.gravitySign, 1)
        XCTAssertGreaterThanOrEqual(count(ev, .modeChanged), 3)
        XCTAssertTrue(p.grounded)
        XCTAssertEqual(p.jumpsRemaining, Sim.maxJumps)
    }
}
