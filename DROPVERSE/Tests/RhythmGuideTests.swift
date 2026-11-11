import XCTest
@testable import Dropverse

final class RhythmGuideTests: XCTestCase {
    func testGridFollowsEachStagesTempoAndStart() {
        // Stage A at 128 BPM (1 grid beat per song beat), stage B a half-time song folded up (2 grid beats per song beat).
        let a = GuideStage(startTau: 0, gridBeats: 16, gridBeatsPerSongBeat: 1)
        let b = GuideStage(startTau: 16 * Sim.beatTau, gridBeats: 16, gridBeatsPerSongBeat: 2)
        let lines = RhythmGuideModel.gridLines(stages: [a, b], from: 0, to: 32 * Sim.beatTau, subdivision: .off)
        let inA = lines.filter { $0.tau < 16 * Sim.beatTau }
        let inB = lines.filter { $0.tau >= 16 * Sim.beatTau - 1e-9 }
        XCTAssertEqual(inA.count, 16)
        XCTAssertEqual(inB.count, 8, "half-time song: one line per song beat = every 2 grid beats")
        XCTAssertEqual(inA.filter { $0.kind == .bar }.count, 4)
        XCTAssertEqual(inB.first?.kind, .bar, "the new song's grid starts on its downbeat at the boundary")
        XCTAssertEqual(inB.first?.tau ?? -1, 16 * Sim.beatTau, accuracy: 1e-9)
    }

    func testSubdivisions() {
        let s = GuideStage(startTau: 0, gridBeats: 4, gridBeatsPerSongBeat: 1)
        let half = RhythmGuideModel.gridLines(stages: [s], from: 0, to: 4 * Sim.beatTau, subdivision: .half)
        XCTAssertEqual(half.count, 8)
        XCTAssertEqual(half.filter { $0.kind == .half }.count, 4)
        let quarter = RhythmGuideModel.gridLines(stages: [s], from: 0, to: 4 * Sim.beatTau, subdivision: .quarter)
        XCTAssertEqual(quarter.count, 16)
        XCTAssertEqual(quarter.filter { $0.kind == .quarter }.count, 8)
    }

    func testGridDoesNotAssumeTimeZero() {
        let s = GuideStage(startTau: 3.3, gridBeats: 8, gridBeatsPerSongBeat: 1)
        let lines = RhythmGuideModel.gridLines(stages: [s], from: 0, to: 10, subdivision: .off)
        XCTAssertEqual(lines.first?.tau ?? -1, 3.3, accuracy: 1e-9)
    }

    func testMarkersComeFromValidatedCues() throws {
        let lib = try PatternLibrary.loadBundled()
        let p = try XCTUnwrap(lib.pattern(id: "dj.kick_snare"))
        var c = Course()
        c.append(p, at: 10, stage: 1)
        let markers = RhythmGuideModel.markers(placed: c.placed, from: 0, to: 100)
        XCTAssertEqual(markers.count, p.cues?.count)
        XCTAssertEqual(markers[0].tau, 10 + 2 * Sim.beatTau, accuracy: 1e-9)
        XCTAssertEqual(markers[1].action, .double)
        // Patterns without validated cues produce no markers.
        let noCue = try XCTUnwrap(lib.patterns.first { $0.cues == nil && $0.entry.mode == .cube })
        var c2 = Course()
        c2.append(noCue, at: 0, stage: 1)
        XCTAssertTrue(RhythmGuideModel.markers(placed: c2.placed, from: -10, to: 100).isEmpty)
    }

    func testMarkerTimingAtDifferentTempos() throws {
        // A cue at beat 2 is reached 2 beats of *real* time after the pattern start at any BPM.
        let lib = try PatternLibrary.loadBundled()
        let p = try XCTUnwrap(lib.pattern(id: "dj.kick_snare"))
        for bpm in [100.0, 128, 174] {
            let k = Sim.tempoFactor(bpm: bpm)
            var c = Course()
            c.append(p, at: 0, stage: 1)
            let m = RhythmGuideModel.markers(placed: c.placed, from: -1, to: 100)[0]
            let realSeconds = m.tau / k
            XCTAssertEqual(realSeconds, 2 * 60 / Sim.foldBPM(bpm), accuracy: 1e-9)
        }
    }

    func testJudgmentWindows() {
        XCTAssertEqual(RhythmGuideModel.judge(deltaSeconds: 0.01), .perfect)
        XCTAssertEqual(RhythmGuideModel.judge(deltaSeconds: -0.05), .great)
        XCTAssertEqual(RhythmGuideModel.judge(deltaSeconds: 0.1), .good)
        XCTAssertEqual(RhythmGuideModel.judge(deltaSeconds: -0.15), .early)
        XCTAssertEqual(RhythmGuideModel.judge(deltaSeconds: 0.15), .late)
        XCTAssertNil(RhythmGuideModel.judge(deltaSeconds: 0.5), "far-off presses are ordinary jumps, not judged")
    }

    func testGuidesDoNotAffectPhysics() throws {
        // The guide model is read-only: generating markers and lines leaves the course unchanged,
        // and the simulation has no dependency on guide settings.
        let lib = try PatternLibrary.loadBundled()
        var c = Course()
        c.append(try XCTUnwrap(lib.pattern(id: "dj.long_gap")), at: 0, stage: 1)
        var a = PlayerState(), b = PlayerState()
        var tau = 0.0
        for i in 0..<300 {
            WorldPhysics.step(course: c, player: &a, tauPrev: tau, dtau: 1.0 / 120, held: i % 50 == 0, pressed: i % 50 == 0)
            _ = RhythmGuideModel.markers(placed: c.placed, from: tau - 1, to: tau + 3)
            _ = RhythmGuideModel.gridLines(stages: [GuideStage(startTau: 0, gridBeats: 8, gridBeatsPerSongBeat: 1)],
                                           from: tau - 1, to: tau + 3, subdivision: .quarter)
            WorldPhysics.step(course: c, player: &b, tauPrev: tau, dtau: 1.0 / 120, held: i % 50 == 0, pressed: i % 50 == 0)
            tau += 1.0 / 120
        }
        XCTAssertEqual(a, b)
    }

    func testSettingsPersistAndOldFilesDecode() throws {
        let old = #"{"musicVolume":0.5,"sfxVolume":0.8,"particleIntensity":"low","reducedFlashing":true,"reducedMotion":false,"cameraShake":1,"audioOffsetMilliseconds":20,"showPerformanceOverlay":false}"#
        let s = try JSONDecoder().decode(GameSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.musicVolume, 0.5)
        XCTAssertFalse(s.showBeatGrid)
        XCTAssertEqual(s.beatSubdivision, .off)
        XCTAssertEqual(s.guideOpacity, 0.65)
        var t = GameSettings()
        t.showBeatGrid = true
        t.beatSubdivision = .quarter
        t.guideOpacity = 0.4
        let round = try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(round, t)
    }
}
