import XCTest
@testable import Dropverse

/// Pattern library, generator and validator tests.
/// The solver tests prove completability by simulation; they mirror Tools/validate_*.py.
final class LevelTests: XCTestCase {
    private static var cachedLibrary: PatternLibrary?

    private func library() throws -> PatternLibrary {
        if let l = Self.cachedLibrary { return l }
        let l = try PatternLibrary.loadBundled()
        Self.cachedLibrary = l
        return l
    }

    /// Deep DFS recursion needs more stack than XCTest's main thread provides.
    private func onLargeStack(_ work: @escaping () -> Void) {
        let done = expectation(description: "large-stack work")
        let thread = Thread {
            work()
            done.fulfill()
        }
        thread.stackSize = 256 << 20
        thread.start()
        wait(for: [done], timeout: 600)
    }

    func testLibraryLoadsAndIsStructurallyValid() throws {
        let lib = try library()
        XCTAssertGreaterThanOrEqual(lib.patterns.count, 45)
        for p in lib.patterns {
            XCTAssertTrue(LevelValidator.templateIssues(p).isEmpty, "\(p.id): \(LevelValidator.templateIssues(p))")
        }
        let kinds = Set(lib.patterns.flatMap { $0.objects.map(\.type) })
        for required in ["spike", "block", "pit", "mblock", "saw", "pendulum", "mhazard", "laser", "gate", "basswall",
                         "eq", "notehazard", "pad", "orb", "portal", "fallblock"] {
            XCTAssertTrue(kinds.contains(required), "no pattern uses \(required)")
        }
    }

    func testEveryPatternIsCompletableAtAllTempos() throws {
        let lib = try library()
        var failures: [String] = []
        onLargeStack {
            for p in lib.patterns {
                for k in [0.70, 1.0, 1.41] where !LevelValidator.provePattern(p, tempoFactor: k) {
                    failures.append("\(p.id) @k=\(k)")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "unsolvable: \(failures)")
    }

    func testPatternsAreNotTrivial() throws {
        // Doing nothing must die in every non-transition pattern.
        let lib = try library()
        for p in lib.patterns where !p.isTransition {
            var course = Course()
            let end = course.append(p, at: 2 * Sim.beatTau, stage: 0) + 2 * Sim.beatTau
            var player = PlayerState(entry: p.entry)
            var tau = 0.0
            while tau < end && !player.dead {
                WorldPhysics.step(course: course, player: &player, tauPrev: tau, dtau: 1.0 / 120, held: false, pressed: false)
                tau += 1.0 / 120
            }
            XCTAssertTrue(player.dead, "\(p.id) can be completed without any input")
        }
    }

    func testGeneratorMatchesReferenceImplementation() throws {
        // Golden sequences produced by Tools/dropverse_gen.py (validate_stages.py prints them).
        let gen = LevelGenerator(library: try library())
        let a = gen.generate(StageRequest(stage: 1, seed: 42, totalBeats: 64)).map(\.pattern.id)
        XCTAssertEqual(a, ["dj.kick_snare", "cube.double_spike_lift", "trans.cube_to_ship", "ship.saws", "ship.corridor", "trans.ship_to_cube"])
        let b = gen.generate(StageRequest(stage: 12, seed: 7, totalBeats: 80)).map(\.pattern.id)
        XCTAssertEqual(b, ["cube.eq_barrier", "cube.saw_narrow_landing", "trans.cube_to_wave", "wave.spike_corridor",
                           "trans.wave_to_cube", "dj.saw_gap", "dj.double_layer", "cube.orb_chain"])
        // Note the settle gap: ship → cube ends at 34, the double-jump pattern waits until 37.
        let c = gen.generate(StageRequest(stage: 5, seed: 99, totalBeats: 72)).map { "\($0.pattern.id)@\($0.beat)" }
        XCTAssertEqual(c, ["cube.bass_walls@4", "cube.pad_launch@13", "trans.cube_to_ship@22", "trans.ship_to_cube@29",
                           "dj.midair_saws@37", "cube.note_hop@46", "dj.note_stairs@55"])
    }

    func testGeneratedStagesAreStructurallyValidAndVaried() throws {
        let lib = try library()
        let gen = LevelGenerator(library: lib)
        for stage in [1, 2, 3, 6, 12, 20, 30] {
            for seed: UInt64 in 0..<40 {
                for beats in [40, 64, 96] {
                    let placed = gen.generate(StageRequest(stage: stage, seed: seed, totalBeats: beats))
                    XCTAssertTrue(LevelValidator.structuralIssues(placed: placed, totalBeats: beats).isEmpty)
                    let ids = placed.map(\.pattern.id)
                    if stage < 9 {
                        XCTAssertTrue(ids.contains("trans.cube_to_ship"), "stage \(stage) has no Surfer section: \(ids)")
                        XCTAssertFalse(placed.contains { $0.pattern.exit.mode == .wave }, "Wave starts at stage 9")
                    }
                    for (x, y) in zip(ids, ids.dropFirst()) {
                        XCTAssertNotEqual(x, y, "immediate repeat")
                    }
                    if stage <= 3 {
                        XCTAssertGreaterThanOrEqual(Set(placed.flatMap { $0.pattern.tags }).count, 4, "stage 1–3 should mix obstacle types")
                    }
                }
            }
        }
    }

    func testDoubleJumpPatternsReallyNeedTheSecondJump() throws {
        let lib = try library()
        var wrong: [String] = []
        onLargeStack {
            for p in lib.patterns where p.requiredJumps == 2 {
                for k in [0.70, 1.0, 1.41] where LevelValidator.provePattern(p, tempoFactor: k, maxJumps: 1) {
                    wrong.append("\(p.id) solvable without the air jump at k=\(k)")
                }
            }
        }
        XCTAssertTrue(wrong.isEmpty, "\(wrong)")
        XCTAssertGreaterThanOrEqual(lib.patterns.filter { $0.requiredJumps == 2 }.count, 8)
    }

    func testTimingCuesAreValidStrategies() throws {
        let lib = try library()
        var bad: [String] = []
        for p in lib.patterns where p.cues != nil {
            for k in [0.70, 1.41] where !LevelValidator.verifyCues(p, tempoFactor: k) {
                bad.append("\(p.id)@\(k)")
            }
            // A double-jump marker may only appear in a pattern that actually needs or uses an air jump in its strategy.
            for cue in p.cues ?? [] { XCTAssertGreaterThanOrEqual(cue.window, 0.06, p.id) }
        }
        XCTAssertTrue(bad.isEmpty, "cue strategies that fail: \(bad)")
        let kickSnare = try XCTUnwrap(lib.pattern(id: "dj.kick_snare"))
        XCTAssertEqual(kickSnare.cues?.prefix(2).map(\.beat), [2.0, 3.0], "jump on the kick, double on the snare")
        XCTAssertEqual(kickSnare.cues?.prefix(2).map(\.action), [.jump, .double])
    }

    func testDoubleJumpNeverFollowsAnUnsettledExit() throws {
        let gen = LevelGenerator(library: try library())
        for stage in [1, 4, 9, 16, 25] {
            for seed: UInt64 in 0..<60 {
                let placed = gen.generate(StageRequest(stage: stage, seed: seed, totalBeats: 96))
                for (a, b) in zip(placed, placed.dropFirst()) where b.pattern.requiredJumps == 2 {
                    let gap = b.beat - (a.beat + a.pattern.beats)
                    XCTAssertGreaterThanOrEqual(gap, a.pattern.settleBeats ?? 0, "\(a.pattern.id) → \(b.pattern.id)")
                }
                for entry in placed where entry.pattern.barAligned == true {
                    XCTAssertEqual(entry.beat % 4, 0)
                }
                if stage >= 1 {
                    XCTAssertTrue(placed.contains { $0.pattern.requiredJumps == 2 }, "stage \(stage) seed \(seed) has no double-jump section")
                }
            }
        }
    }

    func testRetryReproducesTheSameStage() throws {
        let gen = LevelGenerator(library: try library())
        let seed = SeededGenerator.stageSeed(runSeed: 123_456, stage: 4)
        let a = gen.generate(StageRequest(stage: 4, seed: seed, totalBeats: 64)).map { "\($0.pattern.id)@\($0.beat)" }
        let b = gen.generate(StageRequest(stage: 4, seed: seed, totalBeats: 64)).map { "\($0.pattern.id)@\($0.beat)" }
        XCTAssertEqual(a, b)
    }

    func testSampledFullStagesAreCompletable() throws {
        let lib = try library()
        let gen = LevelGenerator(library: lib)
        var failures: [String] = []
        onLargeStack {
            for stage in [1, 5, 13, 22] {
                for seed: UInt64 in 0..<2 {
                    let s = SeededGenerator.stageSeed(runSeed: 2024 + seed, stage: stage)
                    let placed = gen.generate(StageRequest(stage: stage, seed: s, totalBeats: 64))
                    for k in [0.70, 1.41] where !LevelValidator.proveStage(library: lib, placed: placed, totalBeats: 64, tempoFactor: k) {
                        failures.append("stage \(stage) seed \(seed) k \(k)")
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }

    func testTutorialSequenceChains() throws {
        let lib = try library()
        var state = PatternState.base.key
        for step in LevelGenerator.tutorialSteps {
            let p = try XCTUnwrap(lib.pattern(id: step.id), "missing tutorial pattern \(step.id)")
            XCTAssertEqual(p.entry.key, state, "tutorial breaks at \(step.id)")
            state = p.exit.key
        }
        XCTAssertEqual(state, PatternState.base.key)
    }

    func testDifficultyBands() {
        XCTAssertEqual(DifficultyTier(stage: 1), .challenging)
        XCTAssertEqual(DifficultyTier(stage: 3), .challenging)
        XCTAssertEqual(DifficultyTier(stage: 4), .hard)
        XCTAssertEqual(DifficultyTier(stage: 8), .hard)
        XCTAssertEqual(DifficultyTier(stage: 9), .veryHard)
        XCTAssertEqual(DifficultyTier(stage: 15), .veryHard)
        XCTAssertEqual(DifficultyTier(stage: 16), .expert)
    }

    func testShuffleBagAvoidsImmediateRepeats() {
        let url = URL(fileURLWithPath: "/dev/null")
        let tracks = (0..<5).map { i in
            Track(id: "t\(i)", url: url, title: "T\(i)", artist: "A", genre: i % 2 == 0 ? .house : .dubstep, license: nil,
                  cleared: true, manualBPM: nil, manualDropStart: nil, manualDropEnd: nil, fileSize: 0)
        }
        var bag = TrackShuffleBag(tracks: tracks, seed: 9)
        var last: String?
        for _ in 0..<40 {
            let t = bag.next()
            XCTAssertNotNil(t)
            XCTAssertNotEqual(t?.id, last)
            last = t?.id
        }
    }
}
