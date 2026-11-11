import AVFoundation
import Observation
import os
import SpriteKit
import SwiftUI

private let runLog = Logger(subsystem: "com.dropverse.game", category: "Run")

/// Values shown by the gameplay HUD. Updated ~10× per second, not every frame.
struct HUDSnapshot: Equatable {
    var stage: Int
    var score: Int
    var progress: Double
    var difficulty: DifficultyTier
    var trackTitle: String
    var artist: String
    var mode: MovementMode = .cube
    var hint: String?
    var isTutorial = false
}

/// Shown on the Game Over screen.
struct RunResult: Equatable {
    let stagesCleared: Int
    let failedStage: Int
    let highestStageReached: Int
    let finalScore: Int
    let bestScore: Int
    let isNewBest: Bool
    let trackTitle: String
    let artist: String
}

/// Owns one play session: seeds, stage plans, music scheduling, phase and results.
///
/// State machine: loading → playing ⇄ paused, playing → dying → gameOver → (retry | new run) → loading.
/// Successful stages never stop the game: the next stage is generated and its audio is
/// scheduled on the same sample timeline while the current one plays.
@MainActor
@Observable
final class GameCoordinator {
    enum Phase: Equatable { case loading, playing, paused, dying, gameOver, tutorialComplete }
    enum Kind { case run, tutorial }

    static let silentTitle = "Silent Grid"
    static let silentArtist = "No playable tracks · 128 BPM test clock"

    private(set) var phase: Phase = .loading
    private(set) var hud: HUDSnapshot
    private(set) var result: RunResult?
    private(set) var scene: GameScene?
    private(set) var loadingMessage = "Preparing the drop…"
    /// Developer physics overlay values (only updated when the overlay is enabled).
    private(set) var debug = PhysicsDebugSnapshot()

    private let save: SaveManager
    private let music: MusicManager
    private let library: MusicLibrary
    private let patterns: PatternLibrary
    private let onExit: @MainActor () -> Void
    private let runStartStage: Int
    let kind: Kind

    @ObservationIgnored private var runSeed: UInt64
    @ObservationIgnored private var bag: TrackShuffleBag
    @ObservationIgnored private var stageTracks: [Int: Track] = [:]
    @ObservationIgnored private var currentStage: Int
    @ObservationIgnored private var stagesClearedThisRun = 0
    @ObservationIgnored private var scoreAtCurrentStageStart = 0
    @ObservationIgnored private var nextStartSample: AVAudioFramePosition = 0
    @ObservationIgnored private var sceneStageNumbers: [Int] = []
    @ObservationIgnored private var silentClock: MonotonicGameClock?
    @ObservationIgnored private var usingAudio = false
    @ObservationIgnored private var runToken = 0

    init(save: SaveManager, music: MusicManager, library: MusicLibrary, patterns: PatternLibrary,
         startStage: Int, kind: Kind = .run, onExit: @escaping @MainActor () -> Void) {
        self.save = save
        self.music = music
        self.library = library
        self.patterns = patterns
        self.onExit = onExit
        self.kind = kind
        self.runStartStage = startStage
        self.currentStage = startStage
        let seed = UInt64.random(in: .min ... .max)
        self.runSeed = seed
        self.bag = TrackShuffleBag(tracks: library.playableTracks, seed: seed)
        self.hud = HUDSnapshot(stage: startStage, score: 0, progress: 0, difficulty: DifficultyTier(stage: startStage),
                               trackTitle: "", artist: "", isTutorial: kind == .tutorial)
        music.onInterruption = { [weak self] in self?.pause() }
    }

    // MARK: - Scene

    func prepareScene(viewSize: CGSize) {
        guard scene == nil, viewSize.width > 0, viewSize.height > 0 else { return }
        let metrics = SceneMetrics(viewSize: viewSize)
        let skin = CharacterSkin.skin(for: save.progress.selectedSkin)
        let textures = TextureFactory.makeGameTextures(skin: skin, sceneHeight: metrics.sceneSize.height)
        let config = GameSceneConfiguration(metrics: metrics, skin: skin, textures: textures,
                                            effects: EffectSettings(settings: save.settings))
        let newScene = GameScene(configuration: config)
        newScene.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) } // SpriteKit calls back on the main thread
        }
        scene = newScene
        applySettings(save.settings)
        begin(stage: currentStage)
    }

    /// Applies settings that take effect immediately during play.
    func applySettings(_ s: GameSettings) {
        scene?.applyGuideSettings(GuideSettings(s))
        scene?.applyDebug(overlay: s.showPhysicsDebug, bounds: s.showCollisionBounds)
        music.volume = Float(s.musicVolume)
        music.clock.userOffset = s.audioOffsetMilliseconds / 1000
    }

    /// Last flight-recorder dump (written on death), for the debug overlay's copy button.
    var flightRecording: String { scene?.flightRecording ?? "" }

    // MARK: - Commands

    func pause() {
        guard phase == .playing else { return }
        scene?.setSimulationPaused(true)
        if usingAudio { music.pause() } else { silentClock?.pause() }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        if usingAudio && music.engineWasReset {
            // The audio route/engine was rebuilt: the sample timeline restarted, so replay the stage.
            retryStage()
            return
        }
        phase = .playing
        scene?.setSimulationPaused(false)
        if usingAudio { music.resume() } else { silentClock?.resume() }
    }

    /// Replays the current stage with the identical seed, track and layout.
    func retryStage() {
        result = nil
        begin(stage: currentStage)
    }

    func newRun() {
        runSeed = UInt64.random(in: .min ... .max)
        bag = TrackShuffleBag(tracks: library.playableTracks, seed: runSeed)
        stageTracks = [:]
        stagesClearedThisRun = 0
        scoreAtCurrentStageStart = 0
        currentStage = runStartStage
        result = nil
        begin(stage: currentStage)
    }

    func exitToMenu() {
        tearDown()
        onExit()
    }

    func tearDown() {
        runToken += 1
        scene?.stopSimulation()
        scene?.onEvent = nil
        scene?.isPaused = true
        music.stop()
        music.onInterruption = nil
    }

    // MARK: - Stage lifecycle

    private func begin(stage: Int) {
        runToken += 1
        let token = runToken
        phase = .loading
        scene?.stopSimulation()
        music.stop()
        Task { @MainActor in
            await self.startStage(stage, token: token)
        }
    }

    private func startStage(_ stage: Int, token: Int) async {
        guard let scene else { return }
        if kind == .tutorial {
            let plan = tutorialPlan()
            let clock = MonotonicGameClock()
            silentClock = clock
            usingAudio = false
            sceneStageNumbers = [plan.stage]
            hud = HUDSnapshot(stage: 0, score: 0, progress: 0, difficulty: .challenging, trackTitle: "Tutorial",
                              artist: "Silent practice", isTutorial: true)
            clock.start()
            scene.startRun(first: plan, clock: clock, score: 0, tutorialClock: clock)
            phase = .playing
            return
        }

        // Make sure at least one track is analysed before the very first stage.
        if library.playableTracks.isEmpty, let candidate = library.tracks.first(where: { $0.isPlayable }) {
            loadingMessage = "Analysing \(candidate.title)…"
            _ = await library.ensureAnalyzed(candidate)
            guard token == runToken else { return }
            bag = TrackShuffleBag(tracks: library.playableTracks, seed: runSeed)
        }
        let plan = makePlan(stage: stage)
        var segment: PreparedSegment?
        if let track = stageTracks[stage], let analysis = library.analysis(for: track) {
            loadingMessage = "Loading \(track.title)…"
            segment = await prepare(track: track, analysis: analysis, duration: plan.durationSeconds)
            guard token == runToken else { return }
        }
        currentStage = stage
        sceneStageNumbers = [stage]
        nextStartSample = AVAudioFramePosition((plan.durationSeconds * MusicManager.sampleRate).rounded())
        applySettings(save.settings)
        let clock: GameClock
        if let segment {
            usingAudio = true
            silentClock = nil
            music.startRun(with: segment)
            clock = music.clock
        } else {
            usingAudio = false
            let c = MonotonicGameClock()
            c.start()
            silentClock = c
            clock = c
        }
        hud = HUDSnapshot(stage: stage, score: scoreAtCurrentStageStart, progress: 0, difficulty: DifficultyTier(stage: stage),
                          trackTitle: plan.trackTitle, artist: plan.artist)
        scene.startRun(first: plan, clock: clock, score: scoreAtCurrentStageStart)
        phase = .playing
    }

    /// Appends the following stage while the current one plays and schedules its audio
    /// to start on the exact sample where the current drop ends.
    private func appendNextStage(after stage: Int) {
        guard let scene, kind == .run else { return }
        let next = stage + 1
        let plan = makePlan(stage: next)
        scene.appendStage(plan)
        sceneStageNumbers.append(next)
        let startSample = nextStartSample
        nextStartSample += AVAudioFramePosition((plan.durationSeconds * MusicManager.sampleRate).rounded())
        guard usingAudio, let track = stageTracks[next], let analysis = library.analysis(for: track) else { return }
        let token = runToken
        Task { @MainActor in
            guard let segment = await self.prepare(track: track, analysis: analysis, duration: plan.durationSeconds),
                  token == self.runToken else { return }
            self.music.schedule(segment, atSample: startSample)
        }
    }

    private func prepare(track: Track, analysis: TrackAnalysis, duration: Double) async -> PreparedSegment? {
        let url = track.url
        let start = analysis.dropStart
        return await Task.detached(priority: .userInitiated) { () -> PreparedSegment? in
            do {
                return try MusicManager.prepareSegment(url: url, start: start, duration: duration)
            } catch {
                runLog.error("Segment failed for \(track.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    /// Builds the plan for a stage: picks (or reuses) its track, converts the drop to folded
    /// beats, and generates + structurally validates the pattern layout.
    private func makePlan(stage: Int) -> StagePlan {
        if stageTracks[stage] == nil, let t = bag.next() { stageTracks[stage] = t }
        let seed = SeededGenerator.stageSeed(runSeed: runSeed, stage: stage)
        var totalBeats = 64
        var duration = 30.0
        var energy: [Double]?
        var bpm = Sim.referenceBPM
        var songBPM = Sim.referenceBPM
        var theme = WorldTheme.forGenre(Genre.allCases[Int(seed % UInt64(Genre.allCases.count))])
        var title = Self.silentTitle
        var artist = Self.silentArtist
        if let track = stageTracks[stage], let a = library.analysis(for: track) {
            let folded = Sim.foldBPM(a.bpm)
            let ratio = folded / a.bpm
            totalBeats = max(16, Int((Double(a.dropBars * 4) * ratio).rounded()))
            let frames = (a.dropDuration * MusicManager.sampleRate).rounded()
            duration = frames / MusicManager.sampleRate
            let foldedBars = totalBeats / 4
            energy = (0..<foldedBars).map { i in
                let orig = min(a.barEnergy.count - 1, Int(Double(i) / ratio))
                return orig >= 0 ? a.barEnergy[orig] : 0.5
            }
            bpm = folded
            songBPM = a.bpm
            theme = WorldTheme.forGenre(track.genre)
            title = track.title
            artist = track.artist
        }
        let generator = LevelGenerator(library: patterns)
        let k = Double(totalBeats) * Sim.beatTau / duration
        var placed = generator.generate(StageRequest(stage: stage, seed: seed, totalBeats: totalBeats, tempoFactor: k, barEnergy: energy))
        var attempt: UInt64 = 1
        while !LevelValidator.structuralIssues(placed: placed, totalBeats: totalBeats).isEmpty && attempt < 4 {
            runLog.error("Stage \(stage) layout failed structural validation, regenerating")
            placed = generator.generate(StageRequest(stage: stage, seed: seed &+ attempt, totalBeats: totalBeats, tempoFactor: k, barEnergy: energy))
            attempt += 1
        }
        return StagePlan(stage: stage, seed: seed, totalBeats: totalBeats, durationSeconds: duration, barEnergy: energy,
                         theme: theme, trackTitle: title, artist: artist, bpm: bpm, songBPM: songBPM,
                         placed: placed, hints: [], isTutorial: false)
    }

    private func tutorialPlan() -> StagePlan {
        var placed: [(pattern: PatternTemplate, beat: Int)] = []
        var hints: [(beat: Int, text: String)] = []
        var beat = 4
        for step in LevelGenerator.tutorialSteps {
            guard let p = patterns.pattern(id: step.id) else { continue }
            hints.append((max(0, beat - 3), step.hint))
            placed.append((p, beat))
            beat += p.beats + 4
        }
        let total = beat + 4
        return StagePlan(stage: 0, seed: 0, totalBeats: total, durationSeconds: Double(total) * Sim.beatTau, barEnergy: nil,
                         theme: WorldTheme.forGenre(.futureBass), trackTitle: "Tutorial", artist: "Silent practice", bpm: 128,
                         songBPM: 128, placed: placed, hints: hints, isTutorial: true)
    }

    // MARK: - Scene events

    private func handle(_ event: GameSceneEvent) {
        switch event {
        case let .tick(stage, progress, score, mode):
            hud.stage = stage
            hud.progress = progress
            hud.score = score
            hud.mode = mode
            hud.difficulty = DifficultyTier(stage: max(1, stage))

        case let .stageStarted(index, stage):
            if kind == .run, let scene, index == scene.lastStageIndex {
                appendNextStage(after: stage)
            }
            if let track = stageTracks[stage] {
                hud.trackTitle = track.title
                hud.artist = track.artist
            } else if kind == .run {
                hud.trackTitle = Self.silentTitle
                hud.artist = Self.silentArtist
            }

        case let .stageCompleted(stage, score):
            guard kind == .run else { return }
            stagesClearedThisRun += 1
            currentStage = stage + 1
            scoreAtCurrentStageStart = score
            ProgressionManager.recordStageCleared(stage, score: score, progress: &save.progress)
            hud.stage = currentStage
            hud.score = score
            hud.progress = 0
            hud.difficulty = DifficultyTier(stage: currentStage)

        case let .playerDied(_, score):
            hud.score = score
            guard kind == .run else { return }
            phase = .dying
            music.stop()

        case .deathSequenceFinished:
            guard kind == .run else { return }
            let isNewBest = ProgressionManager.recordRunEnded(stageReached: currentStage, finalScore: hud.score,
                                                              progress: &save.progress)
            result = RunResult(stagesCleared: stagesClearedThisRun, failedStage: currentStage,
                               highestStageReached: save.progress.highestStageReached, finalScore: hud.score,
                               bestScore: save.progress.bestScore, isNewBest: isNewBest,
                               trackTitle: hud.trackTitle, artist: hud.artist)
            phase = .gameOver

        case let .hint(text):
            hud.hint = text

        case .tutorialFinished:
            save.progress.tutorialCompleted = true
            phase = .tutorialComplete

        case .doubleJumped:
            let style = CharacterSkin.skin(for: save.progress.selectedSkin).faceStyle
            music.play(.doubleJump(style), volume: Float(save.settings.sfxVolume) * 0.6)

        case .orbHit:
            music.play(.orb, volume: Float(save.settings.sfxVolume) * 0.5)

        case let .judgment(j):
            if j == .perfect { music.play(.judgmentPerfect, volume: Float(save.settings.sfxVolume) * 0.4) }

        case let .debug(snapshot):
            debug = snapshot
        }
    }
}
