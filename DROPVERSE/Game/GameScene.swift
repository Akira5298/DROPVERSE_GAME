import os
import QuartzCore
import SpriteKit
import UIKit

private let sceneLog = Logger(subsystem: "com.dropverse.game", category: "Scene")

/// One stage's worth of music + layout, produced by GameCoordinator.
struct StagePlan {
    let stage: Int
    let seed: UInt64
    /// Length in folded (grid) beats (always whole bars).
    let totalBeats: Int
    /// Exact real duration of the audio segment (or the silent clock).
    let durationSeconds: Double
    let barEnergy: [Double]?
    let theme: WorldTheme
    let trackTitle: String
    let artist: String
    /// Folded (gameplay grid) tempo.
    let bpm: Double
    /// The song's own detected tempo (before folding into 90–180).
    let songBPM: Double
    let placed: [(pattern: PatternTemplate, beat: Int)]
    let hints: [(beat: Int, text: String)]
    let isTutorial: Bool

    /// Reference seconds per real second for this stage (exactly consistent with the audio).
    var tempoFactor: Double { Double(totalBeats) * Sim.beatTau / durationSeconds }
    var gridBeatsPerSongBeat: Double { songBPM > 0 ? bpm / songBPM : 1 }
}

enum GameSceneEvent {
    case tick(stage: Int, progress: Double, score: Int, mode: MovementMode)
    case stageStarted(index: Int, stage: Int)
    case stageCompleted(stage: Int, score: Int)
    case playerDied(stage: Int, score: Int)
    case deathSequenceFinished
    case hint(String?)
    case tutorialFinished
    case doubleJumped
    case orbHit
    case judgment(TimingJudgment)
    case debug(PhysicsDebugSnapshot)
}

struct GameSceneConfiguration {
    var metrics: SceneMetrics
    var skin: CharacterSkin
    var textures: GameTextures
    var effects: EffectSettings
}

/// Gameplay scene: runs the deterministic simulation against the game clock in fixed
/// 120 Hz steps, renders the world, and reports events. Navigation, audio and persistence
/// live in GameCoordinator.
///
/// There are no SpriteKit physics bodies anywhere: collision is the custom simulation in
/// `WorldPhysics`, and sprites only *display* its state, so the two can never disagree about
/// where the ground is — provided everything simulated is also drawn (see ObstacleRenderer.draws).
final class GameScene: SKScene {
    private struct StageRuntime {
        let plan: StagePlan
        let index: Int
        let startReal: Double
        let startTau: Double
        var endTau: Double { startTau + Double(plan.totalBeats) * Sim.beatTau }
        var endReal: Double { startReal + plan.durationSeconds }
        var k: Double { plan.tempoFactor }
    }

    enum SimulationState { case idle, running, dying, stopped }

    var onEvent: ((GameSceneEvent) -> Void)?

    private let config: GameSceneConfiguration
    private var clock: GameClock = MonotonicGameClock()
    private var tutorialClock: MonotonicGameClock?

    private var course = Course()
    private var stages: [StageRuntime] = []
    private var guideStages: [GuideStage] = []
    private var currentStageIndex = 0
    private var player = PlayerState()
    private var simTau: Double = 0
    private var held = false
    private var pressPending = false
    private var activeTouches = 0
    private(set) var state: SimulationState = .idle

    private var scoreAtStageStart = 0
    private var bonus = 0
    private var score = 0
    private var lastTick: Double = -1
    private var lastFrameTime: TimeInterval = 0
    private var lastBeatIndex = -1
    private var lastHint: String?
    private var expression = ExpressionController()
    private var judgedMarkers = Set<Int>()

    // Diagnostics
    private var recorder = FlightRecorder()
    private var debugEnabled = false
    private var lastDebugPush: Double = -1
    private var lastEventName = ""
    private var lagSeconds = 0.0

    // Nodes
    private let cameraNode = SKCameraNode()
    private var backdrop: WorldBackdrop!
    private var guides: RhythmGuideRenderer!
    private var obstacles: ObstacleRenderer!
    private var rig: PlayerRig!
    private var trail: TrailEmitter!
    private var effects: EffectsLayer!
    private let debugBounds = DebugBoundsRenderer()
    private var beatBuffer: [(x: Double, index: Int)] = []
    private var built = false

    private var metrics: SceneMetrics { config.metrics }

    init(configuration: GameSceneConfiguration) {
        self.config = configuration
        super.init(size: configuration.metrics.sceneSize)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = NeonPalette.background.uiColor
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("GameScene is created in code only") }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        buildIfNeeded()
    }

    private func buildIfNeeded() {
        guard !built else { return }
        built = true
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        // Layers (back to front): decorative world 0, guide grid + markers 10, obstacles 20,
        // trails 25, player 30, effects & judgments 40, debug bounds 45.
        backdrop = WorldBackdrop(size: size, playerX: metrics.playerX, textures: config.textures, theme: WorldTheme.forGenre(.other))
        backdrop.root.zPosition = 0
        addChild(backdrop.root)
        guides = RhythmGuideRenderer(textures: config.textures)
        guides.layer.zPosition = 10
        addChild(guides.layer)
        obstacles = ObstacleRenderer(textures: config.textures, theme: WorldTheme.forGenre(.other))
        obstacles.layer.zPosition = 20
        addChild(obstacles.layer)
        trail = TrailEmitter(skin: config.skin, textures: config.textures)
        trail.intensity = CGFloat(config.effects.particleIntensity)
        trail.layer.zPosition = 25
        addChild(trail.layer)
        rig = PlayerRig(textures: config.textures, skin: config.skin)
        rig.zPosition = 30
        addChild(rig)
        effects = EffectsLayer(size: size, textures: config.textures, camera: cameraNode, settings: config.effects)
        effects.layer.zPosition = 40
        addChild(effects.layer)
        for label in guides.judgmentNodes { effects.layer.addChild(label) }
        addChild(debugBounds.layer)
    }

    // MARK: - Settings (applied live)

    func applyGuideSettings(_ s: GuideSettings) {
        buildIfNeeded()
        guides.apply(s)
        guideSettings = s
    }

    private var guideSettings = GuideSettings()

    func applyDebug(overlay: Bool, bounds: Bool) {
        debugEnabled = overlay
        debugBounds.enabled = bounds
    }

    var flightRecording: String { recorder.lastDump }

    // MARK: - Run control

    /// Starts a run (or a retry) with `first` at real time 0 on `clock`.
    func startRun(first: StagePlan, clock: GameClock, score: Int, tutorialClock: MonotonicGameClock? = nil) {
        buildIfNeeded()
        removeAllActions()
        self.clock = clock
        self.tutorialClock = tutorialClock
        course = Course()
        stages = []
        guideStages = []
        backdrop.discardNotes(before: .infinity)
        obstacles.reset()
        trail.reset()
        effects.reset()
        recorder.reset()
        judgedMarkers.removeAll()
        player = PlayerState()
        simTau = 0
        held = false
        pressPending = false
        activeTouches = 0
        scoreAtStageStart = score
        self.score = score
        bonus = 0
        lastTick = -1
        lastBeatIndex = -1
        lastHint = nil
        lagSeconds = 0
        expression = ExpressionController()
        currentStageIndex = 0
        rig.isHidden = false
        rig.alpha = 1
        appendStage(first)
        backdrop.apply(theme: first.theme, animated: false)
        obstacles.setTheme(first.theme)
        guides.setTheme(first.theme.primary)
        isPaused = false
        state = .running
        render(dt: 0)
        onEvent?(.stageStarted(index: 0, stage: first.stage))
    }

    /// Appends the next stage directly after the last one (seamless progression). The floor is
    /// one continuous support across the boundary: `Course.floorSegments` only splits at pits.
    func appendStage(_ plan: StagePlan) {
        let startReal = stages.last?.endReal ?? 0
        let startTau = stages.last?.endTau ?? 0
        let runtime = StageRuntime(plan: plan, index: stages.count, startReal: startReal, startTau: startTau)
        course.beginStage(at: startTau)
        for entry in plan.placed {
            course.append(entry.pattern, at: startTau + Double(entry.beat) * Sim.beatTau, stage: plan.stage)
        }
        var beatsX: [Double] = []
        beatsX.reserveCapacity(plan.totalBeats + 1)
        for b in 0...plan.totalBeats {
            beatsX.append(course.speed.x(at: startTau + Double(b) * Sim.beatTau))
        }
        backdrop.addNotes(beatsX: beatsX, energy: plan.barEnergy, seed: plan.seed)
        stages.append(runtime)
        guideStages.append(GuideStage(startTau: startTau, gridBeats: plan.totalBeats, gridBeatsPerSongBeat: plan.gridBeatsPerSongBeat))
    }

    var lastStageIndex: Int { stages.count - 1 }

    func setSimulationPaused(_ paused: Bool) {
        // Player state (including jumps remaining) is untouched while paused; only touches are reset.
        if !paused {
            activeTouches = 0
            held = false
        }
        isPaused = paused
    }

    func stopSimulation() {
        state = .stopped
        removeAllActions()
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .running else { return }
        activeTouches += touches.count
        held = true
        // Every touch-down is a new tap (a second finger counts too). The first jump is applied
        // on the very next simulation step — no gesture recogniser, no waiting for a double tap.
        pressPending = true
        if let touch = touches.first { judgePress(touch: touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches = max(0, activeTouches - touches.count)
        held = activeTouches > 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    /// Optional timing feedback against validated cues. Never touches the simulation.
    private func judgePress(touch: UITouch) {
        guard guideSettings.showMarkers, guideSettings.showJudgments,
              let idx = stageIndex(forTau: simTau) else { return }
        let k = stages[idx].k
        let age = max(0, CACurrentMediaTime() - touch.timestamp) + guideSettings.inputLatency
        let pressTau = simTau - age * k
        let window = 0.3 * k
        var best: GuideMarker?
        for m in RhythmGuideModel.markers(placed: course.placed, from: pressTau - window, to: pressTau + window)
        where !judgedMarkers.contains(m.id) {
            if best == nil || abs(m.tau - pressTau) < abs(best!.tau - pressTau) { best = m }
        }
        guard let m = best, let j = RhythmGuideModel.judge(deltaSeconds: (pressTau - m.tau) / k) else { return }
        judgedMarkers.insert(m.id)
        guides.showJudgment(j, at: CGPoint(x: metrics.playerX, y: CGFloat(player.y)))
        onEvent?(.judgment(j))
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastFrameTime == 0 ? 1.0 / 60.0 : min(0.1, currentTime - lastFrameTime)
        lastFrameTime = currentTime
        guard state == .running, !stages.isEmpty else {
            if state == .dying { render(dt: CGFloat(dt)) }
            return
        }
        let t = clock.currentTime
        let targetTau = tau(forReal: t)
        var steps = 0
        // Catch up in fixed steps only. The simulation is NEVER teleported forward: v0.2 jumped
        // simTau straight to the clock after a long hitch, which could drop the player inside a
        // block or past a pit edge without simulating it (deaths "with no obstacle"). If a hitch
        // exceeds the per-frame budget, the remaining steps run on the following frames.
        while state == .running, steps < GameConstants.maxCatchUpSteps {
            let k = stageIndex(forTau: simTau).map { stages[$0].k } ?? 1
            let dtau = k * GameConstants.fixedTimeStep
            guard simTau + dtau <= targetTau else { break }
            stepSimulation(dtau: dtau)
            steps += 1
        }
        let k = stageIndex(forTau: simTau).map { stages[$0].k } ?? 1
        lagSeconds = max(0, (targetTau - simTau) / k)
        render(dt: CGFloat(dt))
        if state == .running, t - lastTick >= GameConstants.hudUpdateInterval {
            lastTick = t
            let s = stages[currentStageIndex]
            let progress = min(1, max(0, (simTau - s.startTau) / (s.endTau - s.startTau)))
            onEvent?(.tick(stage: s.plan.stage, progress: progress, score: score, mode: player.mode))
        }
        if debugEnabled, t - lastDebugPush >= 0.1 {
            lastDebugPush = t
            onEvent?(.debug(debugSnapshot()))
        }
    }

    private func tau(forReal t: Double) -> Double {
        guard let last = stages.last else { return 0 }
        for s in stages.reversed() where t >= s.startReal {
            return min(s.startTau + (t - s.startReal) * s.k, last.endTau - 1e-6)
        }
        return max(0, t * (stages.first?.k ?? 1))
    }

    private func stageIndex(forTau tau: Double) -> Int? {
        for s in stages.reversed() where tau >= s.startTau { return s.index }
        return stages.first?.index
    }

    private func stepSimulation(dtau: Double) {
        let pressed = pressPending
        pressPending = false
        let previousSupport = player.supportID
        let events = WorldPhysics.step(course: course, player: &player, tauPrev: simTau, dtau: dtau,
                                       held: held, pressed: pressed)
        simTau += dtau
        let sample = FlightSample(tau: simTau, x: course.speed.x(at: simTau), y: player.y, vy: player.vy,
                                  grounded: player.grounded, jumps: player.jumpsRemaining, supportID: player.supportID,
                                  mode: player.mode, gravity: player.gravitySign, events: events, held: held, pressed: pressed)
        recorder.record(sample)
        if events.contains(.lostSupport) {
            FlightRecorder.logUnexpectedGroundLoss(sample, previousSupport: previousSupport)
            lastEventName = "lost support (walked off \(FlightRecorder.describeSupport(previousSupport)))"
        }
        handle(events)
        if player.dead {
            lastEventName = "died: \(player.lastContact)"
            _ = recorder.dump(reason: "death (\(player.deathCause.rawValue): \(player.lastContact))",
                              seed: stages[currentStageIndex].plan.seed)
            killPlayer()
            return
        }
        if let idx = stageIndex(forTau: simTau), idx != currentStageIndex {
            completeStage(newIndex: idx)
        }
        let s = stages[currentStageIndex]
        let localBeats = (simTau - s.startTau) / Sim.beatTau
        score = scoreAtStageStart + bonus + Int(localBeats * Double(GameConstants.pointsPerBeat))
        if s.plan.isTutorial {
            updateHint(localBeat: localBeats, plan: s.plan)
            if simTau >= s.endTau - Sim.beatTau {
                state = .stopped
                onEvent?(.tutorialFinished)
            }
        }
    }

    private func handle(_ events: StepEvents) {
        guard !events.isEmpty else { return }
        let pos = CGPoint(x: metrics.playerX, y: CGFloat(player.y))
        let skin = config.skin
        let feet = CGPoint(x: pos.x, y: pos.y - CGFloat(player.half * player.gravitySign))
        if events.contains(.jumped) {
            lastEventName = "jump"
            expression.react(.jump, at: simTau, duration: 0.18)
            effects.burst(at: feet, colors: [skin.primary.uiColor, skin.secondary.uiColor], count: 4, speed: 40...120, life: 0.3)
        }
        if events.contains(.doubleJumped) {
            lastEventName = "double jump"
            doubleJumpEffect(at: pos, feet: feet)
        }
        if events.contains(.landed) {
            rig.land()
            expression.react(.land, at: simTau, duration: 0.22)
            effects.shockwave(at: feet, color: skin.primary.uiColor, radius: skin.faceStyle == .crusher ? 90 : 55, duration: 0.3)
            if skin.faceStyle == .crusher { effects.shake(intensity: 0.25) }
        }
        if events.contains(.ledgeCaught) { lastEventName = "ledge catch" }
        if events.contains(.pad) {
            bonus += GameConstants.padBonus
            lastEventName = "pad"
            expression.react(.boost, at: simTau, duration: 0.35)
            effects.shockwave(at: feet, color: RGB(hex: 0xFFD23D).uiColor, radius: 90)
        }
        if events.contains(.orb) {
            bonus += GameConstants.orbBonus
            lastEventName = "orb"
            expression.react(.orb, at: simTau, duration: 0.35)
            effects.shockwave(at: pos, color: RGB(hex: 0xFFD23D).uiColor, radius: 110)
            effects.burst(at: pos, colors: [.white, skin.accent.uiColor], count: 8, speed: 60...200, life: 0.4)
            onEvent?(.orbHit)
        }
        if events.contains(.gravityChanged) {
            lastEventName = "gravity"
            expression.react(.gravity, at: simTau, duration: 0.45)
            effects.flash(color: RGB(hex: 0xFFD23D).uiColor, peak: 0.12, duration: 0.3)
        }
        if events.contains(.modeChanged) {
            lastEventName = "mode → \(player.mode.rawValue)"
            expression.react(.modeSwitch, at: simTau, duration: 0.5)
            effects.shockwave(at: pos, color: skin.secondary.uiColor, radius: 200, duration: 0.5)
            effects.flash(color: skin.secondary.uiColor, peak: 0.15, duration: 0.35)
        }
        if events.contains(.sizeChanged) {
            expression.react(.modeSwitch, at: simTau, duration: 0.3)
            effects.shockwave(at: pos, color: RGB(hex: 0xFF6BD8).uiColor, radius: 80)
        }
    }

    /// Distinct per-skin double-jump feedback: second burst in a different colour, a glowing ring
    /// under the cube, a quick extra spin, a brighter aura and the strongest jump expression.
    /// Purely visual — none of it touches the simulation.
    private func doubleJumpEffect(at pos: CGPoint, feet: CGPoint) {
        let skin = config.skin
        expression.react(.doubleJump, at: simTau, duration: 0.4)
        rig.doubleJump(reducedMotion: config.effects.reducedMotion)
        switch skin.faceStyle {
        case .reactor:
            effects.shockwave(at: feet, color: skin.secondary.uiColor, radius: 70, duration: 0.35)
            effects.burst(at: feet, colors: [skin.secondary.uiColor, .white], count: 10, speed: 80...220, life: 0.35)
        case .glitch:
            effects.shockwave(at: feet, color: skin.primary.uiColor, radius: 60, duration: 0.25)
            effects.burst(at: feet, colors: [skin.primary.uiColor, skin.secondary.uiColor, .black], count: 14, speed: 60...260, life: 0.3)
        case .crusher:
            effects.shockwave(at: feet, color: RGB(hex: 0xFFD23D).uiColor, radius: 110, duration: 0.4)
            effects.burst(at: feet, colors: [skin.primary.uiColor, RGB(hex: 0xFFD23D).uiColor], count: 12, speed: 40...160, life: 0.45)
            effects.shake(intensity: 0.2)
        case .prism:
            effects.shockwave(at: feet, color: skin.accent.uiColor, radius: 80, duration: 0.4)
            effects.burst(at: feet, colors: [skin.primary.uiColor, skin.secondary.uiColor, skin.accent.uiColor, .white],
                          count: 12, speed: 70...210, life: 0.45)
        }
        onEvent?(.doubleJumped)
    }

    private func updateHint(localBeat: Double, plan: StagePlan) {
        var text: String?
        for h in plan.hints where Double(h.beat) <= localBeat { text = h.text }
        if text != lastHint {
            lastHint = text
            onEvent?(.hint(text))
        }
    }

    private func completeStage(newIndex: Int) {
        let finished = stages[currentStageIndex]
        currentStageIndex = newIndex
        let next = stages[newIndex]
        score = scoreAtStageStart + bonus + finished.plan.totalBeats * GameConstants.pointsPerBeat + GameConstants.stageClearBonus
        scoreAtStageStart = score
        bonus = 0
        // Cleanup only removes objects and pits that are fully behind the camera; the floor is
        // rebuilt from the remaining pits, so it stays one continuous support.
        course.discard(before: course.speed.x(at: simTau) - 2500)
        backdrop.discardNotes(before: course.speed.x(at: simTau) - 2500)
        backdrop.apply(theme: next.plan.theme, animated: true)
        obstacles.setTheme(next.plan.theme)
        guides.setTheme(next.plan.theme.primary)
        effects.flash(color: next.plan.theme.primary.uiColor, peak: 0.25, duration: 0.5)
        effects.shockwave(at: CGPoint(x: metrics.playerX, y: size.height / 2), color: next.plan.theme.primary.uiColor, radius: 520, duration: 0.6)
        if !config.effects.reducedMotion {
            backdrop.root.run(.sequence([
                .moveBy(x: 14, y: 0, duration: 0.03), .moveBy(x: -26, y: 0, duration: 0.04),
                .moveBy(x: 18, y: 0, duration: 0.03), .moveBy(x: -6, y: 0, duration: 0.03),
            ]))
        }
        expression.react(.celebrate, at: simTau, duration: 0.6)
        onEvent?(.stageCompleted(stage: finished.plan.stage, score: score))
        onEvent?(.stageStarted(index: newIndex, stage: next.plan.stage))
    }

    private func killPlayer() {
        state = .dying
        let pos = CGPoint(x: metrics.playerX, y: CGFloat(player.y))
        rig.setExpression(.dead)
        onEvent?(.playerDied(stage: stages[currentStageIndex].plan.stage, score: score))
        let skin = config.skin
        effects.flash(color: .white, peak: 0.4, duration: 0.25)
        effects.shake(intensity: 1)
        let colors: [UIColor]
        switch skin.faceStyle {
        case .reactor: colors = [skin.primary.uiColor, skin.secondary.uiColor, .white]
        case .glitch: colors = [skin.primary.uiColor, skin.secondary.uiColor, .black]
        case .crusher: colors = [skin.primary.uiColor, RGB(hex: 0xFFD23D).uiColor, skin.secondary.uiColor]
        case .prism: colors = [skin.primary.uiColor, skin.secondary.uiColor, skin.accent.uiColor, .white]
        }
        let isTutorial = stages[currentStageIndex].plan.isTutorial
        run(.sequence([
            .wait(forDuration: 0.14),
            .run { [weak self] in
                guard let self else { return }
                self.rig.isHidden = true
                self.effects.burst(at: pos, colors: colors, count: 26, speed: 120...360, life: 0.7)
                self.effects.shockwave(at: pos, color: skin.primary.uiColor, radius: 140, duration: 0.5)
            },
            .wait(forDuration: isTutorial ? 0.5 : 0.7),
            .run { [weak self] in
                guard let self, self.state == .dying else { return }
                if isTutorial {
                    self.rewindTutorial()
                } else {
                    self.state = .stopped
                    self.onEvent?(.deathSequenceFinished)
                }
            },
        ]))
    }

    /// Tutorial deaths restart the current lesson instantly instead of ending the run.
    private func rewindTutorial() {
        guard let checkpoint = course.placed.last(where: { $0.tauStart <= simTau }) else { return }
        let resumeTau = max(0, checkpoint.tauStart - 2 * Sim.beatTau)
        player = PlayerState(entry: checkpoint.pattern.entry)
        simTau = resumeTau
        tutorialClock?.seek(to: resumeTau)
        held = false
        pressPending = false
        activeTouches = 0
        judgedMarkers.removeAll()
        rig.isHidden = false
        trail.reset()
        state = .running
    }

    // MARK: - Diagnostics

    private func debugSnapshot() -> PhysicsDebugSnapshot {
        PhysicsDebugSnapshot(
            x: course.speed.x(at: simTau), y: player.y, vy: player.vy, grounded: player.grounded,
            jumps: player.jumpsRemaining, supportCount: player.supportCount,
            support: FlightRecorder.describeSupport(player.supportID), mode: player.mode.rawValue,
            gravity: player.gravitySign > 0 ? "normal" : "flipped", mini: player.mini,
            lastContact: player.lastContact, lastEvent: lastEventName,
            seed: stages.isEmpty ? 0 : stages[currentStageIndex].plan.seed, tau: simTau, lagMs: lagSeconds * 1000)
    }

    // MARK: - Rendering

    private func render(dt: CGFloat) {
        guard built, !stages.isEmpty else { return }
        let playerWX = course.speed.x(at: simTau)
        let toScreen: (Double) -> CGFloat = { [metrics] wx in metrics.playerX + CGFloat(wx - playerWX) }
        let tauToScreen: (Double) -> CGFloat = { [course] tau in toScreen(course.speed.x(at: tau)) }
        let beatPos = simTau / Sim.beatTau
        let beatIndex = Int(beatPos.rounded(.down))
        let phase = beatPos - Double(beatIndex)
        let downbeat = beatIndex % 4 == 0
        let pulse = CGFloat(pow(1 - phase, 3)) * (downbeat ? 1 : 0.6)
        let s = stages[min(currentStageIndex, stages.count - 1)]
        let bar = Int((simTau - s.startTau) / Sim.beatTau / 4)
        let energy = CGFloat(s.plan.barEnergy.flatMap { bar >= 0 && bar < $0.count ? $0[bar] : nil } ?? 0.6)
        if beatIndex != lastBeatIndex {
            lastBeatIndex = beatIndex
            if state == .running && downbeat && energy > 0.55 { effects.kick(strength: energy) }
        }

        let leftTau = simTau - Double(metrics.playerX) / Sim.speed - Sim.beatTau
        let rightTau = simTau + Double(size.width - metrics.playerX) / Sim.speed + Sim.beatTau
        beatBuffer.removeAll(keepingCapacity: true)
        var b = Int((leftTau / Sim.beatTau).rounded(.down))
        while Double(b) * Sim.beatTau <= rightTau {
            beatBuffer.append((course.speed.x(at: Double(b) * Sim.beatTau), b))
            b += 1
        }
        backdrop.update(tau: simTau, playerWX: playerWX, beats: beatBuffer, beatPulse: pulse, energy: energy,
                        reducedMotion: config.effects.reducedMotion, reducedFlashing: config.effects.reducedFlashing)
        guides.update(stages: guideStages, placed: course.placed, tau: simTau, leftTau: leftTau, rightTau: rightTau,
                      tauToScreen: tauToScreen, dt: dt)
        obstacles.update(course: course, tau: simTau,
                         viewMinX: playerWX - Double(metrics.playerX) - 120,
                         viewMaxX: playerWX + Double(size.width - metrics.playerX) + 120,
                         toScreen: toScreen, beatPulse: pulse, reducedFlashing: config.effects.reducedFlashing,
                         usedTriggers: player.usedTriggers)

        let boosting = course.speed.mult(at: simTau) > 1.01
        if state == .running {
            let face = expression.update(at: simTau, player: player, nearDanger: nearDanger(playerWX: playerWX), boosting: boosting)
            rig.setExpression(face)
        }
        rig.position = CGPoint(x: metrics.playerX, y: CGFloat(player.y))
        rig.update(player: player, dt: dt, beatPulse: pulse, reducedMotion: config.effects.reducedMotion)
        trail.update(dt: dt, playerWX: playerWX, playerY: CGFloat(player.y), mode: player.mode, mini: player.mini,
                     toScreen: toScreen, alive: state == .running)
        debugBounds.update(course: course, player: player, tau: simTau, playerScreenX: metrics.playerX,
                           playerWX: playerWX, viewWidth: size.width)
    }

    /// True when a hazard is just ahead of the player at a similar height.
    private func nearDanger(playerWX: Double) -> Bool {
        var i = course.firstIndex(minXAtLeast: playerWX - Course.maxObjectSpan)
        while i < course.objects.count {
            let o = course.objects[i]
            i += 1
            if o.minX > playerWX + 110 { break }
            guard o.isHazard, o.maxX > playerWX else { continue }
            let y: Double
            switch o.kind {
            case .saw, .pendulum: y = o.cy
            default: y = (o.y0 + max(o.y1, o.y0 + 30)) / 2
            }
            if abs(y - player.y) < 90 { return true }
        }
        return false
    }
}
