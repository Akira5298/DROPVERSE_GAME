import SpriteKit
import UIKit

/// Timing facts the guide needs about one stage (all derived from the audio-locked StagePlan).
struct GuideStage: Equatable {
    /// Course time of the stage's first (downbeat) grid beat.
    let startTau: Double
    /// Stage length in grid (folded) beats.
    let gridBeats: Int
    /// Grid beats per *song* beat: 1 normally, 2 for half-time songs folded up (87 → 174),
    /// 0.5 for very fast songs folded down. Lines are drawn on the song's real beats.
    let gridBeatsPerSongBeat: Double
}

enum GuideLineKind: Equatable { case bar, beat, half, quarter }

struct GuideMarker: Equatable {
    let id: Int
    let tau: Double
    /// Half-width of the validated timing window, in course time.
    let windowTau: Double
    let action: PatternCue.Action
}

enum TimingJudgment: String, Equatable {
    case perfect = "PERFECT", great = "GREAT", good = "GOOD", early = "EARLY", late = "LATE"
}

/// Pure timing model for the Rhythm Timing Guide. No SpriteKit, so it is unit-tested directly.
/// Everything is expressed in course time (tau), which the scene derives from the audio clock;
/// screen x then follows `x = referenceX + (worldX(tau) − worldX(now))`, i.e. the spec's
/// `referenceX + (actionTime − audioTime) × scrollSpeed` including speed-portal sections.
enum RhythmGuideModel {
    /// Judgment windows in milliseconds (|input − cue|).
    static let perfectMs = 35.0
    static let greatMs = 70.0
    static let goodMs = 110.0
    /// Presses farther than this from every cue are ordinary jumps and are not judged.
    static let judgeRangeMs = 200.0

    static func gridLines(stages: [GuideStage], from a: Double, to b: Double, subdivision: BeatSubdivision) -> [(tau: Double, kind: GuideLineKind)] {
        var out: [(tau: Double, kind: GuideLineKind)] = []
        for s in stages {
            let songBeat = s.gridBeatsPerSongBeat * Sim.beatTau
            guard songBeat > 0 else { continue }
            let end = s.startTau + Double(s.gridBeats) * Sim.beatTau
            let lo = max(a, s.startTau)
            let hi = min(b, end)
            guard hi > lo else { continue }
            let step: Double
            switch subdivision {
            case .off: step = 1
            case .half: step = 0.5
            case .quarter: step = 0.25
            }
            var j = ((lo - s.startTau) / songBeat / step).rounded(.down) * step
            while true {
                let tau = s.startTau + j * songBeat
                if tau > hi || tau >= end - 1e-9 { break }
                if tau >= lo - 1e-9 {
                    let frac = j - j.rounded(.down)
                    let kind: GuideLineKind
                    if abs(frac) < 1e-9 {
                        kind = Int(j.rounded()) % 4 == 0 ? .bar : .beat
                    } else if abs(frac - 0.5) < 1e-9 {
                        kind = .half
                    } else {
                        kind = .quarter
                    }
                    out.append((tau, kind))
                }
                j += step
            }
        }
        return out
    }

    static func markers(placed: [PlacedPattern], from a: Double, to b: Double) -> [GuideMarker] {
        var out: [GuideMarker] = []
        for p in placed where p.tauEnd >= a && p.tauStart <= b {
            guard let cues = p.pattern.cues else { continue }
            for (i, cue) in cues.enumerated() {
                let tau = p.tauStart + cue.beat * Sim.beatTau
                guard tau >= a - 1, tau <= b + 1 else { continue }
                out.append(GuideMarker(id: p.serial * 32 + i, tau: tau, windowTau: cue.window * Sim.beatTau, action: cue.action))
            }
        }
        return out
    }

    /// - Parameter deltaSeconds: input time − cue time in real seconds (negative = early).
    static func judge(deltaSeconds: Double) -> TimingJudgment? {
        let ms = deltaSeconds * 1000
        let a = abs(ms)
        if a > judgeRangeMs { return nil }
        if a <= perfectMs { return .perfect }
        if a <= greatMs { return .great }
        if a <= goodMs { return .good }
        return ms < 0 ? .early : .late
    }

    static func color(for action: PatternCue.Action) -> RGB {
        switch action {
        case .jump: return RGB(hex: 0x19F0FF)
        case .double: return RGB(hex: 0xFF2BD6)
        case .orb: return RGB(hex: 0xFFD23D)
        case .gravity: return RGB(hex: 0x9B6BFF)
        }
    }
}

/// Settings snapshot the scene applies live.
struct GuideSettings: Equatable {
    var showGrid = false
    var showMarkers = false
    var subdivision: BeatSubdivision = .off
    var opacity: Double = 0.65
    var showJudgments = true
    var inputLatency: Double = 0 // seconds

    init() {}

    init(_ s: GameSettings) {
        showGrid = s.showBeatGrid
        showMarkers = s.showTapGuides
        subdivision = s.beatSubdivision
        opacity = s.guideOpacity
        showJudgments = s.showTimingJudgments
        inputLatency = s.inputLatencyMilliseconds / 1000
    }
}

/// Renders the guide grid and action markers with pooled nodes, only inside the viewport.
/// Sits between the decorative background and the obstacles (z 10).
final class RhythmGuideRenderer {
    let layer = SKNode()
    private let gridLayer = SKNode()
    private let markerLayer = SKNode()
    private var lines: [SKSpriteNode] = []
    private var markerNodes: [SKNode] = []
    private var judgmentLabels: [SKLabelNode] = []
    private var judgmentIndex = 0
    private let textures: GameTextures
    private var settings = GuideSettings()
    private var themeColor = NeonPalette.cyan
    private var previousThemeColor = NeonPalette.cyan
    private var blend: CGFloat = 1

    init(textures: GameTextures) {
        self.textures = textures
        layer.addChild(gridLayer)
        layer.addChild(markerLayer)
        markerLayer.zPosition = 1
        for _ in 0..<72 {
            let l = SKSpriteNode(color: .white, size: CGSize(width: 2, height: CGFloat(Sim.playHeight)))
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.position.y = CGFloat(Sim.floorY)
            l.colorBlendFactor = 1
            l.isHidden = true
            gridLayer.addChild(l)
            lines.append(l)
        }
        for _ in 0..<16 {
            let root = SKNode()
            let band = SKSpriteNode(color: .white, size: CGSize(width: 10, height: CGFloat(Sim.playHeight)))
            band.name = "band"
            band.anchorPoint = CGPoint(x: 0.5, y: 0)
            band.alpha = 0.16
            root.addChild(band)
            let line = SKSpriteNode(color: .white, size: CGSize(width: 4, height: CGFloat(Sim.playHeight)))
            line.name = "line"
            line.anchorPoint = CGPoint(x: 0.5, y: 0)
            line.blendMode = .add
            root.addChild(line)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.name = "label"
            label.fontSize = 13
            label.verticalAlignmentMode = .bottom
            label.position = CGPoint(x: 0, y: CGFloat(Sim.playHeight) + 4)
            root.addChild(label)
            root.position.y = CGFloat(Sim.floorY)
            root.isHidden = true
            markerLayer.addChild(root)
            markerNodes.append(root)
        }
        for _ in 0..<3 {
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.fontSize = 20
            l.alpha = 0
            l.zPosition = 60
            judgmentLabels.append(l)
        }
    }

    /// Judgment labels live above the player, so the scene adds them to its effects layer.
    var judgmentNodes: [SKLabelNode] { judgmentLabels }

    func apply(_ s: GuideSettings) {
        settings = s
        layer.alpha = CGFloat(s.opacity)
        gridLayer.isHidden = !s.showGrid
        markerLayer.isHidden = !s.showMarkers
    }

    func setTheme(_ color: RGB) {
        guard color != themeColor else { return }
        previousThemeColor = themeColor
        themeColor = color
        blend = 0
    }

    func update(stages: [GuideStage], placed: [PlacedPattern], tau: Double, leftTau: Double, rightTau: Double,
                tauToScreen: (Double) -> CGFloat, dt: CGFloat) {
        blend = min(1, blend + dt / 0.6)
        let tint = blendRGB(previousThemeColor, themeColor, blend)
        var li = 0
        if settings.showGrid {
            for line in RhythmGuideModel.gridLines(stages: stages, from: leftTau, to: rightTau, subdivision: settings.subdivision) {
                guard li < lines.count else { break }
                let node = lines[li]
                li += 1
                node.isHidden = false
                node.position.x = tauToScreen(line.tau)
                switch line.kind {
                case .bar:
                    node.texture = nil
                    node.size.width = 3
                    node.color = mix(NeonPalette.cyan, tint, 0.3)
                    node.alpha = 0.95
                case .beat:
                    node.texture = nil
                    node.size.width = 1.5
                    node.color = mix(NeonPalette.violet, tint, 0.3)
                    node.alpha = 0.7
                case .half:
                    node.texture = textures.dashedLine
                    node.size.width = 2
                    node.color = mix(NeonPalette.violet, tint, 0.3)
                    node.alpha = 0.4
                case .quarter:
                    node.texture = textures.dottedLine
                    node.size.width = 2
                    node.color = NeonPalette.textSecondary.uiColor
                    node.alpha = 0.28
                }
            }
        }
        for i in li..<lines.count { lines[i].isHidden = true }

        var mi = 0
        if settings.showMarkers {
            for m in RhythmGuideModel.markers(placed: placed, from: leftTau, to: rightTau) {
                guard mi < markerNodes.count else { break }
                let node = markerNodes[mi]
                mi += 1
                node.isHidden = false
                let x = tauToScreen(m.tau)
                node.position.x = x
                let color = RhythmGuideModel.color(for: m.action).uiColor
                let passed = tau > m.tau + m.windowTau
                if let band = node.childNode(withName: "band") as? SKSpriteNode {
                    band.size.width = max(4, tauToScreen(m.tau + m.windowTau) - tauToScreen(m.tau - m.windowTau))
                    band.color = color
                    band.alpha = passed ? 0.05 : 0.16
                }
                if let line = node.childNode(withName: "line") as? SKSpriteNode {
                    line.color = color
                    line.alpha = passed ? 0.2 : 0.95
                }
                if let label = node.childNode(withName: "label") as? SKLabelNode {
                    switch m.action {
                    case .jump: label.text = "JUMP"
                    case .double: label.text = "2×"
                    case .orb: label.text = "ORB"
                    case .gravity: label.text = "GRAV"
                    }
                    label.fontColor = color
                }
            }
        }
        for i in mi..<markerNodes.count { markerNodes[i].isHidden = true }
    }

    func showJudgment(_ j: TimingJudgment, at p: CGPoint) {
        guard settings.showJudgments else { return }
        let label = judgmentLabels[judgmentIndex]
        judgmentIndex = (judgmentIndex + 1) % judgmentLabels.count
        label.removeAllActions()
        label.text = j.rawValue
        label.fontColor = {
            switch j {
            case .perfect: return NeonPalette.lime.uiColor
            case .great: return NeonPalette.cyan.uiColor
            case .good: return NeonPalette.textPrimary.uiColor
            case .early, .late: return NeonPalette.orange.uiColor
            }
        }()
        label.position = CGPoint(x: p.x, y: p.y + 58)
        label.alpha = 1
        label.setScale(0.8)
        label.run(.sequence([
            .group([.scale(to: 1.05, duration: 0.12), .moveBy(x: 0, y: 18, duration: 0.5)]),
            .fadeOut(withDuration: 0.25),
        ]))
    }

    private func blendRGB(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
        let t = Double(t)
        return RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    private func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> UIColor {
        let t = Double(t)
        return UIColor(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t, alpha: 1)
    }
}

extension RGB {
    /// Component initializer (0...1), used for blending theme colours.
    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}
