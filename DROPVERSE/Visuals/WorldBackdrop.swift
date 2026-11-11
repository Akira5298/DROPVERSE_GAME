import SpriteKit
import UIKit

/// A decorative MIDI note in the background roll (not interactive, deliberately dim and
/// borderless so it never reads as a platform).
struct DecoNote {
    let x0: Double
    let x1: Double
    let lane: Int
    let velocity: Double
}

/// The DAW-inspired world: layered parallax, pitch lanes, beat grid with bar numbers,
/// decorative notes with velocity bars, automation curve, sequencer panels, EQ towers,
/// keyboard with track labels and a reactive waveform band under the floor.
final class WorldBackdrop {
    let root = SKNode()
    private let far = SKNode()      // 0.15x parallax
    private let mid = SKNode()      // 0.4x parallax
    private let near = SKNode()     // 1.0x (piano roll plane)
    private let fixed = SKNode()

    private let size: CGSize
    private let playerX: CGFloat
    private let textures: GameTextures
    private var theme: WorldTheme

    private var laneTiles: [SKSpriteNode] = []
    private var beatLines: [SKSpriteNode] = []
    private var barLabels: [SKLabelNode] = []
    private var notePool: [SKSpriteNode] = []
    private var velocityPool: [SKSpriteNode] = []
    private var automationDots: [SKSpriteNode] = []
    private var panels: [SKSpriteNode] = []
    private var eqTowers: [[SKSpriteNode]] = []
    private var waveBars: [SKSpriteNode] = []
    private let farGlowA: SKSpriteNode
    private let farGlowB: SKSpriteNode
    private let playhead = SKSpriteNode()
    private let floorBand: SKSpriteNode
    private let floorEdge = SKSpriteNode()
    private let ceilingEdge = SKSpriteNode()
    private let keyboard: SKSpriteNode

    private(set) var notes: [DecoNote] = []

    init(size: CGSize, playerX: CGFloat, textures: GameTextures, theme: WorldTheme) {
        self.size = size
        self.playerX = playerX
        self.textures = textures
        self.theme = theme
        farGlowA = SKSpriteNode(texture: textures.glowDot)
        farGlowB = SKSpriteNode(texture: textures.glowDot)
        floorBand = SKSpriteNode(color: NeonPalette.ground.uiColor(alpha: 0.96), size: CGSize(width: size.width, height: CGFloat(Sim.floorY)))
        keyboard = SKSpriteNode(texture: textures.keyboard, size: CGSize(width: 92, height: size.height))
        build()
        apply(theme: theme, animated: false)
    }

    private func build() {
        for (layer, z) in [(far, CGFloat(0)), (mid, CGFloat(1)), (near, CGFloat(2)), (fixed, CGFloat(5))] {
            layer.zPosition = z
            root.addChild(layer)
        }
        // Far: soft colour fields.
        for (glow, x) in [(farGlowA, size.width * 0.3), (farGlowB, size.width * 0.8)] {
            glow.size = CGSize(width: 700, height: 520)
            glow.position = CGPoint(x: x, y: size.height * 0.55)
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0.18
            far.addChild(glow)
        }
        // Mid: holographic sequencer panels and EQ towers.
        for i in 0..<4 {
            let p = SKSpriteNode(texture: textures.sequencerPanel, size: CGSize(width: 300, height: 90))
            p.alpha = 0.45
            p.position = CGPoint(x: CGFloat(i) * 520, y: i.isMultiple(of: 2) ? 470 : 360)
            mid.addChild(p)
            panels.append(p)
        }
        for t in 0..<3 {
            var bars: [SKSpriteNode] = []
            for b in 0..<7 {
                let bar = SKSpriteNode(color: .white, size: CGSize(width: 14, height: 40))
                bar.anchorPoint = CGPoint(x: 0.5, y: 0)
                bar.alpha = 0.22
                bar.position = CGPoint(x: CGFloat(t) * 700 + CGFloat(b) * 18, y: CGFloat(Sim.floorY))
                bar.colorBlendFactor = 1
                mid.addChild(bar)
                bars.append(bar)
            }
            eqTowers.append(bars)
        }
        // Near: lanes + grid + notes.
        let tileW: CGFloat = 64
        for i in 0..<(Int(size.width / tileW) + 2) {
            let t = SKSpriteNode(texture: textures.lanesTile, size: CGSize(width: tileW, height: size.height))
            t.anchorPoint = .zero
            t.position = CGPoint(x: CGFloat(i) * tileW, y: 0)
            t.colorBlendFactor = 0.18
            near.addChild(t)
            laneTiles.append(t)
        }
        for _ in 0..<28 {
            let l = SKSpriteNode(color: NeonPalette.beatLine.uiColor, size: CGSize(width: 1.5, height: CGFloat(Sim.playHeight)))
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.position.y = CGFloat(Sim.floorY)
            l.zPosition = 1
            near.addChild(l)
            beatLines.append(l)
        }
        for _ in 0..<8 {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.fontSize = 13
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.fontColor = NeonPalette.textSecondary.uiColor
            label.position.y = CGFloat(Sim.ceilingY) - 6
            label.zPosition = 2
            near.addChild(label)
            barLabels.append(label)
        }
        for _ in 0..<48 {
            let n = SKSpriteNode(texture: textures.decoNote)
            n.centerRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            n.anchorPoint = CGPoint(x: 0, y: 0.5)
            n.colorBlendFactor = 1
            n.zPosition = 1.5
            n.isHidden = true
            near.addChild(n)
            notePool.append(n)
            let v = SKSpriteNode(color: .white, size: CGSize(width: 3, height: 20))
            v.anchorPoint = CGPoint(x: 0.5, y: 0)
            v.colorBlendFactor = 1
            v.isHidden = true
            v.zPosition = 6
            fixed.addChild(v)
            velocityPool.append(v)
        }
        for _ in 0..<44 {
            let d = SKSpriteNode(texture: textures.glowDot, size: CGSize(width: 9, height: 9))
            d.colorBlendFactor = 1
            d.blendMode = .add
            d.zPosition = 1.8
            near.addChild(d)
            automationDots.append(d)
        }
        // Fixed: floor band with waveform, edges, playhead, keyboard.
        floorBand.anchorPoint = .zero
        floorBand.zPosition = 3
        fixed.addChild(floorBand)
        for i in 0..<64 {
            let b = SKSpriteNode(color: .white, size: CGSize(width: max(2, size.width / 64 - 4), height: 10))
            b.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.position = CGPoint(x: CGFloat(i) * size.width / 64, y: CGFloat(Sim.floorY) * 0.42)
            b.colorBlendFactor = 1
            b.alpha = 0.55
            b.zPosition = 4
            fixed.addChild(b)
            waveBars.append(b)
        }
        for edge in [floorEdge, ceilingEdge] {
            edge.size = CGSize(width: size.width, height: 3)
            edge.anchorPoint = CGPoint(x: 0, y: 0.5)
            edge.zPosition = 7
            fixed.addChild(edge)
        }
        floorEdge.position = CGPoint(x: 0, y: CGFloat(Sim.floorY))
        ceilingEdge.position = CGPoint(x: 0, y: CGFloat(Sim.ceilingY))
        let ceilingBand = SKSpriteNode(color: NeonPalette.ground.uiColor(alpha: 0.9),
                                       size: CGSize(width: size.width, height: size.height - CGFloat(Sim.ceilingY)))
        ceilingBand.anchorPoint = .zero
        ceilingBand.position = CGPoint(x: 0, y: CGFloat(Sim.ceilingY))
        ceilingBand.zPosition = 3
        fixed.addChild(ceilingBand)
        playhead.size = CGSize(width: 2, height: CGFloat(Sim.playHeight))
        playhead.anchorPoint = CGPoint(x: 0.5, y: 0)
        playhead.position = CGPoint(x: playerX, y: CGFloat(Sim.floorY))
        playhead.blendMode = .add
        playhead.zPosition = 2
        fixed.addChild(playhead)
        keyboard.anchorPoint = .zero
        keyboard.zPosition = 8
        fixed.addChild(keyboard)
    }

    func apply(theme: WorldTheme, animated: Bool) {
        self.theme = theme
        let duration = animated ? 0.6 : 0
        for t in laneTiles { t.run(.colorize(with: theme.laneTint.uiColor, colorBlendFactor: 0.28, duration: duration)) }
        farGlowA.run(.colorize(with: theme.primary.uiColor, colorBlendFactor: 1, duration: duration))
        farGlowB.run(.colorize(with: theme.secondary.uiColor, colorBlendFactor: 1, duration: duration))
        for tower in eqTowers { for b in tower { b.color = theme.accent.uiColor } }
        for b in waveBars { b.color = theme.primary.uiColor }
        for d in automationDots { d.color = theme.secondary.uiColor }
        playhead.color = theme.primary.uiColor
        floorEdge.color = theme.primary.uiColor
        ceilingEdge.color = theme.secondary.uiColor
    }

    /// Adds seeded decorative notes for a stage between world x positions.
    func addNotes(beatsX: [Double], energy: [Double]?, seed: UInt64) {
        var rng = SeededGenerator(seed: seed ^ 0xDEC0)
        var lane = 14
        var i = 0
        while i < beatsX.count - 1 {
            lane = min(20, max(8, lane + rng.nextInt(below: 7) - 3))
            let len = [1, 1, 2, 1, 4][rng.nextInt(below: 5)]
            let j = min(beatsX.count - 1, i + len)
            let bar = i / 4
            let e = energy.flatMap { bar < $0.count ? $0[bar] : nil } ?? 0.6
            notes.append(DecoNote(x0: beatsX[i], x1: beatsX[j], lane: lane, velocity: 0.35 + 0.65 * e))
            if rng.nextDouble() < 0.3 {
                notes.append(DecoNote(x0: beatsX[i], x1: beatsX[j], lane: lane - 4, velocity: 0.3 + 0.5 * e))
            }
            i = j
        }
    }

    func discardNotes(before x: Double) {
        notes.removeAll { $0.x1 < x }
    }

    /// - Parameters:
    ///   - playerWX: player's world x.
    ///   - beatXs: world x of upcoming/visible beats with their global beat index.
    func update(tau: Double, playerWX: Double, beats: [(x: Double, index: Int)], beatPulse: CGFloat,
                energy: CGFloat, reducedMotion: Bool, reducedFlashing: Bool) {
        let shift = CGFloat(playerWX)
        let toScreen: (Double) -> CGFloat = { [playerX] wx in playerX + CGFloat(wx) - shift }
        let flash: CGFloat = reducedFlashing ? 0.3 : 1

        // Parallax layers wrap around.
        let farShift = reducedMotion ? 0 : shift * 0.15
        far.position.x = sin(farShift / 300) * 60
        let midShift = reducedMotion ? 0 : shift * 0.4
        let span: CGFloat = 2080
        for (i, p) in panels.enumerated() {
            var x = CGFloat(i) * 520 - midShift.truncatingRemainder(dividingBy: span)
            if x < -300 { x += span }
            p.position.x = x
        }
        for (t, tower) in eqTowers.enumerated() {
            var base = CGFloat(t) * 700 + 260 - midShift.truncatingRemainder(dividingBy: 2100)
            if base < -200 { base += 2100 }
            for (b, bar) in tower.enumerated() {
                bar.position.x = base + CGFloat(b) * 18
                let wobble = 0.5 + 0.5 * sin(tau * 7 + Double(b) * 0.9 + Double(t))
                bar.size.height = 30 + CGFloat(wobble) * 120 * (0.4 + energy) + 60 * beatPulse * flash
            }
        }
        farGlowA.alpha = 0.12 + 0.12 * energy + 0.08 * beatPulse * flash
        farGlowB.alpha = 0.1 + 0.1 * energy

        // Lanes.
        let tileW: CGFloat = 64
        var start = (-shift).truncatingRemainder(dividingBy: tileW)
        if start > 0 { start -= tileW }
        for (i, t) in laneTiles.enumerated() { t.position.x = start + CGFloat(i) * tileW }

        // Beat lines + bar labels.
        var li = 0
        var labelIndex = 0
        for beat in beats {
            let sx = toScreen(beat.x)
            guard sx > -4, sx < size.width + 4 else { continue }
            if li < beatLines.count {
                let line = beatLines[li]
                li += 1
                line.isHidden = false
                line.position.x = sx
                let isBar = beat.index % 4 == 0
                line.size.width = isBar ? 2.5 : 1.2
                line.color = isBar ? NeonPalette.barLine.uiColor : NeonPalette.beatLine.uiColor
                line.alpha = isBar ? 0.9 : 0.6
                if isBar, labelIndex < barLabels.count {
                    let label = barLabels[labelIndex]
                    labelIndex += 1
                    label.isHidden = false
                    label.text = "\(beat.index / 4 + 1)"
                    label.position.x = sx + 4
                }
            }
        }
        for i in li..<beatLines.count { beatLines[i].isHidden = true }
        for i in labelIndex..<barLabels.count { barLabels[i].isHidden = true }

        // Decorative notes and their velocity bars.
        var ni = 0
        for n in notes {
            let x0 = toScreen(n.x0), x1 = toScreen(n.x1)
            if x1 < 0 { continue }
            if x0 > size.width { break }
            guard ni < notePool.count else { break }
            let node = notePool[ni]
            let vel = velocityPool[ni]
            ni += 1
            let y = CGFloat(Sim.floorY) + CGFloat(n.lane) * PianoRollMetrics.laneHeight * 0.75 - 40
            node.isHidden = false
            node.position = CGPoint(x: x0, y: y)
            node.size = CGSize(width: max(10, x1 - x0 - 3), height: 13)
            let lit = x0 <= playerX && x1 >= playerX
            node.color = (lit ? theme.glow : (n.lane % 2 == 0 ? theme.primary : theme.accent)).uiColor
            node.alpha = lit ? 0.75 : CGFloat(0.12 + 0.2 * n.velocity)
            vel.isHidden = false
            vel.position = CGPoint(x: x0 + 2, y: 12)
            vel.size.height = CGFloat(n.velocity) * 40 * (lit ? 1.4 : 1)
            vel.color = node.color
            vel.alpha = lit ? 0.9 : 0.4
        }
        for i in ni..<notePool.count {
            notePool[i].isHidden = true
            velocityPool[i].isHidden = true
        }

        // Automation curve (dots along a slowly evolving curve in world space).
        let spacing = size.width / CGFloat(automationDots.count - 1)
        for (i, d) in automationDots.enumerated() {
            let sx = CGFloat(i) * spacing
            let wx = Double(sx - playerX + shift)
            let y = 520 + 40 * sin(wx / 260 + tau * 0.4) + 22 * sin(wx / 97)
            d.position = CGPoint(x: sx, y: CGFloat(y))
            d.alpha = 0.35 + 0.3 * beatPulse * flash
        }

        // Waveform band reacts to the beat and the bar energy.
        let count = waveBars.count
        for (i, b) in waveBars.enumerated() {
            let wx = Double(CGFloat(i) * size.width / CGFloat(count) - playerX + shift)
            let seedish = sin(wx * 0.071) * 0.5 + sin(wx * 0.023 + 1.3) * 0.5
            let distance = abs(CGFloat(i) * size.width / CGFloat(count) - playerX) / size.width
            let h = 6 + (24 + 46 * energy) * CGFloat(abs(seedish)) + 34 * beatPulse * (1 - distance) * flash
            b.size.height = h
        }
        playhead.alpha = 0.2 + 0.5 * beatPulse * flash
        floorEdge.alpha = 0.7 + 0.3 * beatPulse
    }
}
