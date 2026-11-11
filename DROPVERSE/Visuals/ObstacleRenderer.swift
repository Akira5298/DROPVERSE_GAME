import SpriteKit
import UIKit

/// Draws course objects. Nodes are pooled per kind and recycled as objects scroll in and
/// out of view, so the per-frame cost is positioning only.
///
/// Readability contract: safe, standable surfaces are teal/green with a bright top edge;
/// everything lethal is red/magenta with spikes, teeth or stripes; interactives are
/// yellow/pink/blue rings or pads; portals are tall labelled ellipses.
final class ObstacleRenderer {
    let layer = SKNode()
    private let textures: GameTextures
    private var active: [Int: SKNode] = [:]
    private var pools: [ObjectKind: [SKNode]] = [:]
    private var visible = Set<Int>()
    private var theme: WorldTheme

    /// Exhaustive by construction (no `default`): adding an ObjectKind without a visual is a
    /// compile error. Regression guard for the invisible-pit bug.
    static func draws(_ kind: ObjectKind) -> Bool {
        switch kind {
        case .spike, .block, .noteBlock, .pillar, .movingBlock, .fallingPlatform, .pit,
             .hazardBlock, .noteHazard, .saw, .pendulum, .laser, .gate, .bassWall,
             .pad, .orb, .portal, .speedPortal:
            return true
        }
    }

    init(textures: GameTextures, theme: WorldTheme) {
        self.textures = textures
        self.theme = theme
    }

    func setTheme(_ theme: WorldTheme) {
        self.theme = theme
    }

    func reset() {
        for (_, node) in active { recycle(node) }
        active.removeAll()
    }

    /// - Parameters:
    ///   - toScreen: maps world x to scene x.
    ///   - beatPulse: 0...1, decays after each beat (for music-reactive glow).
    func update(course: Course, tau: Double, viewMinX: Double, viewMaxX: Double,
                toScreen: (Double) -> CGFloat, beatPulse: CGFloat, reducedFlashing: Bool, usedTriggers: Set<Int>) {
        visible.removeAll(keepingCapacity: true)
        var i = course.firstIndex(minXAtLeast: viewMinX - Course.maxObjectSpan)
        while i < course.objects.count {
            let o = course.objects[i]
            i += 1
            if o.minX > viewMaxX { break }
            if o.maxX < viewMinX { continue }
            visible.insert(o.id)
            let node: SKNode
            if let existing = active[o.id] {
                node = existing
            } else {
                node = acquire(o)
                active[o.id] = node
            }
            place(node, o, tau: tau, toScreen: toScreen, pulse: beatPulse, reducedFlashing: reducedFlashing,
                  used: usedTriggers.contains(o.id))
        }
        if active.count > visible.count {
            for (id, node) in active where !visible.contains(id) {
                recycle(node)
                active[id] = nil
            }
        }
    }

    // MARK: - Pooling

    private func acquire(_ o: CourseObject) -> SKNode {
        let node: SKNode
        if var pool = pools[o.kind], let reused = pool.popLast() {
            pools[o.kind] = pool
            node = reused
        } else {
            node = make(o.kind)
            layer.addChild(node)
        }
        configure(node, o)
        node.isHidden = false
        return node
    }

    private func recycle(_ node: SKNode) {
        node.isHidden = true
        node.removeAllActions()
        guard let kind = node.userData?["kind"] as? String, let k = ObjectKind(rawValue: kind) else { return }
        pools[k, default: []].append(node)
    }

    private func sprite(_ texture: SKTexture, name: String? = nil) -> SKSpriteNode {
        let s = SKSpriteNode(texture: texture)
        s.name = name
        return s
    }

    private func make(_ kind: ObjectKind) -> SKNode {
        let root = SKNode()
        root.userData = ["kind": kind.rawValue]
        switch kind {
        case .spike:
            break // children created in configure (count varies)
        case .pit:
            let void = SKSpriteNode(color: UIColor(red: 0.01, green: 0.0, blue: 0.03, alpha: 1), size: CGSize(width: 10, height: 10))
            void.name = "body"
            void.anchorPoint = .zero
            root.addChild(void)
            let glow = sprite(textures.glowDot, name: "glow")
            glow.color = NeonPalette.hazard.uiColor
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.anchorPoint = CGPoint(x: 0.5, y: 1)
            root.addChild(glow)
            for name in ["rimA", "rimB"] {
                let rim = SKSpriteNode(color: NeonPalette.hazard.uiColor, size: CGSize(width: 4, height: 10))
                rim.name = name
                rim.anchorPoint = CGPoint(x: 0.5, y: 0)
                root.addChild(rim)
            }
        case .block, .pillar, .noteBlock, .movingBlock, .fallingPlatform, .hazardBlock, .noteHazard, .gate, .bassWall:
            let s = SKSpriteNode()
            s.name = "body"
            s.anchorPoint = .zero
            root.addChild(s)
            if kind == .movingBlock || kind == .noteBlock || kind == .fallingPlatform {
                let glow = sprite(textures.glowDot, name: "glow")
                glow.blendMode = .add
                glow.alpha = 0
                root.addChild(glow)
            }
        case .saw:
            root.addChild(sprite(textures.saw, name: "body"))
        case .pendulum:
            let chain = SKSpriteNode(color: UIColor(white: 0.8, alpha: 0.7), size: CGSize(width: 3, height: 10))
            chain.name = "chain"
            chain.anchorPoint = CGPoint(x: 0.5, y: 1)
            root.addChild(chain)
            let ball = sprite(textures.spikedBall, name: "ball")
            root.addChild(ball)
            let pivot = sprite(textures.emitter, name: "pivot")
            pivot.size = CGSize(width: 18, height: 18)
            root.addChild(pivot)
        case .laser:
            let beam = sprite(textures.laserBeam, name: "beam")
            beam.blendMode = .add
            root.addChild(beam)
            root.addChild(sprite(textures.emitter, name: "capA"))
            root.addChild(sprite(textures.emitter, name: "capB"))
        case .pad:
            let s = sprite(textures.pad, name: "body")
            s.anchorPoint = CGPoint(x: 0, y: 0)
            s.colorBlendFactor = 1
            root.addChild(s)
            let glow = sprite(textures.glowDot, name: "glow")
            glow.blendMode = .add
            root.addChild(glow)
        case .orb:
            let ring = sprite(textures.orb, name: "body")
            ring.colorBlendFactor = 1
            root.addChild(ring)
            let halo = sprite(textures.glowDot, name: "glow")
            halo.blendMode = .add
            root.addChild(halo)
        case .portal:
            root.addChild(sprite(textures.portals[.cube] ?? textures.ring, name: "body"))
            let shimmer = sprite(textures.glowDot, name: "glow")
            shimmer.blendMode = .add
            root.addChild(shimmer)
        case .speedPortal:
            let s = sprite(textures.speedPortal, name: "body")
            s.colorBlendFactor = 1
            root.addChild(s)
        }
        return root
    }

    private func configure(_ node: SKNode, _ o: CourseObject) {
        let w = CGFloat(o.x1 - o.x0)
        let h = CGFloat(o.y1 - o.y0)
        switch o.kind {
        case .spike:
            while node.children.count < o.count {
                let s = sprite(textures.spike)
                let full = CGFloat(Sim.spikeWidth) + TextureFactory.spikePad * 2
                s.size = CGSize(width: full, height: full)
                s.anchorPoint = CGPoint(x: 0.5, y: TextureFactory.spikePad / full)
                node.addChild(s)
            }
            for (i, child) in node.children.enumerated() {
                child.isHidden = i >= o.count
                child.position = CGPoint(x: CGFloat(Sim.spikeWidth) * (CGFloat(i) + 0.5), y: 0)
                child.yScale = o.downward ? -1 : 1
            }
        case .pit:
            let floorH = CGFloat(Sim.floorY)
            (node.childNode(withName: "body") as? SKSpriteNode)?.size = CGSize(width: w, height: floorH + 2)
            if let glow = node.childNode(withName: "glow") as? SKSpriteNode {
                glow.size = CGSize(width: w * 1.1, height: 70)
                glow.position = CGPoint(x: w / 2, y: floorH)
                glow.alpha = 0.35
            }
            for (name, x) in [("rimA", CGFloat(0)), ("rimB", w)] {
                if let rim = node.childNode(withName: name) as? SKSpriteNode {
                    rim.size = CGSize(width: 4, height: floorH)
                    rim.position = CGPoint(x: x, y: 0)
                }
            }
        case .block, .pillar, .noteBlock, .movingBlock, .fallingPlatform, .hazardBlock, .noteHazard:
            guard let body = node.childNode(withName: "body") as? SKSpriteNode else { return }
            let texture: SKTexture
            switch o.kind {
            case .block: texture = textures.block
            case .pillar: texture = textures.pillar
            case .fallingPlatform: texture = textures.fallingPlatform
            case .noteBlock, .movingBlock: texture = textures.noteBlock
            case .hazardBlock: texture = textures.hazardBlock
            default: texture = textures.noteHazard
            }
            body.texture = texture
            body.centerRect = (o.kind == .noteBlock || o.kind == .movingBlock || o.kind == .noteHazard || o.kind == .fallingPlatform)
                ? GameTextures.noteCenter : GameTextures.blockCenter
            body.alpha = 1
            body.size = CGSize(width: max(w, 8), height: max(h, 8))
            if let glow = node.childNode(withName: "glow") as? SKSpriteNode {
                glow.size = CGSize(width: w * 1.2, height: 40)
                glow.position = CGPoint(x: w / 2, y: h)
                glow.color = WorldTheme.safe.uiColor
                glow.colorBlendFactor = 1
            }
        case .gate:
            guard let body = node.childNode(withName: "body") as? SKSpriteNode else { return }
            body.texture = textures.gate
            body.centerRect = GameTextures.blockCenter
            body.size = CGSize(width: max(w, 10), height: h)
        case .bassWall:
            guard let body = node.childNode(withName: "body") as? SKSpriteNode else { return }
            body.texture = textures.bassWall
            body.centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.5)
            body.size = CGSize(width: max(w, 10), height: 10)
            body.color = o.variant == "eq" ? theme.secondary.uiColor : NeonPalette.hazard.uiColor
            body.colorBlendFactor = o.variant == "eq" ? 0.45 : 0
        case .saw:
            (node.childNode(withName: "body") as? SKSpriteNode)?.size = CGSize(width: o.radius * 2.1, height: o.radius * 2.1)
        case .pendulum:
            (node.childNode(withName: "ball") as? SKSpriteNode)?.size = CGSize(width: o.radius * 2.2, height: o.radius * 2.2)
            if let chain = node.childNode(withName: "chain") as? SKSpriteNode {
                chain.size = CGSize(width: 3, height: CGFloat(o.length))
            }
        case .laser:
            break // geometry set per frame (charge state)
        case .pad:
            let color = o.variant == "pink" ? RGB(hex: 0xFF6BD8) : RGB(hex: 0xFFD23D)
            if let body = node.childNode(withName: "body") as? SKSpriteNode {
                body.size = CGSize(width: 40, height: 16)
                body.color = color.uiColor
                body.yScale = o.downward ? -1 : 1
                body.position = CGPoint(x: 0, y: o.downward ? 14 : 0)
            }
            if let glow = node.childNode(withName: "glow") as? SKSpriteNode {
                glow.size = CGSize(width: 60, height: 60)
                glow.color = color.uiColor
                glow.colorBlendFactor = 1
                glow.position = CGPoint(x: 20, y: 8)
            }
        case .orb:
            let color: RGB = o.variant == "pink" ? RGB(hex: 0xFF6BD8) : (o.variant == "gravity" ? RGB(hex: 0x3DC8FF) : RGB(hex: 0xFFD23D))
            if let ring = node.childNode(withName: "body") as? SKSpriteNode {
                ring.size = CGSize(width: 56, height: 56)
                ring.color = color.uiColor
            }
            if let glow = node.childNode(withName: "glow") as? SKSpriteNode {
                glow.size = CGSize(width: 96, height: 96)
                glow.color = color.uiColor
                glow.colorBlendFactor = 1
            }
        case .portal:
            if let body = node.childNode(withName: "body") as? SKSpriteNode, let kind = o.portal {
                body.texture = textures.portals[kind]
                body.size = CGSize(width: 74, height: CGFloat(Sim.playHeight) + 10)
                body.position = CGPoint(x: 0, y: CGFloat(Sim.floorY + Sim.playHeight / 2))
            }
            if let glow = node.childNode(withName: "glow") as? SKSpriteNode {
                glow.size = CGSize(width: 160, height: CGFloat(Sim.playHeight))
                glow.position = CGPoint(x: 0, y: CGFloat(Sim.floorY + Sim.playHeight / 2))
                glow.color = portalColor(o.portal).uiColor
                glow.colorBlendFactor = 1
            }
        case .speedPortal:
            if let body = node.childNode(withName: "body") as? SKSpriteNode {
                body.size = CGSize(width: 64, height: 180)
                body.position = CGPoint(x: 0, y: CGFloat(Sim.floorY + Sim.playHeight / 2))
                body.color = (o.speedMult > 1 ? NeonPalette.orange : NeonPalette.lime).uiColor
            }
        }
    }

    private func portalColor(_ kind: PortalKind?) -> RGB {
        switch kind {
        case .ship: return NeonPalette.magenta
        case .wave: return NeonPalette.cyan
        case .gravityFlip: return RGB(hex: 0xFFD23D)
        case .gravityNormal: return RGB(hex: 0x3D9BFF)
        case .mini: return RGB(hex: 0xFF6BD8)
        case .big: return RGB(hex: 0x6BFF9E)
        default: return NeonPalette.lime
        }
    }

    // MARK: - Per-frame placement

    private func place(_ node: SKNode, _ o: CourseObject, tau: Double, toScreen: (Double) -> CGFloat,
                       pulse: CGFloat, reducedFlashing: Bool, used: Bool) {
        let flash: CGFloat = reducedFlashing ? 0.35 : 1
        switch o.kind {
        case .pit:
            node.position = CGPoint(x: toScreen(o.x0), y: 0)
            node.childNode(withName: "glow")?.alpha = 0.25 + 0.25 * pulse * flash
        case .spike, .block, .pillar, .noteBlock, .movingBlock, .fallingPlatform, .hazardBlock, .noteHazard:
            let r = o.rect(tau)
            var x = toScreen(r.0)
            if let until = o.beatsUntilFall(tau), let body = node.childNode(withName: "body") {
                // Telegraph: shake during the last beat before the drop, then fade while falling.
                if until > 0 && until < 1 { x += CGFloat(sin(tau * 90)) * 2.5 * CGFloat(1 - until) }
                body.alpha = until < 0 ? max(0.25, 1 + CGFloat(until) * 0.6) : 1
            }
            node.position = CGPoint(x: x, y: CGFloat(o.kind == .spike ? o.y0 + o.offset(tau).dy : r.2))
            if let glow = node.childNode(withName: "glow") {
                glow.alpha = 0.15 + 0.35 * pulse * flash
            }
        case .gate:
            node.position = CGPoint(x: toScreen(o.x0), y: CGFloat(o.y0))
            guard let body = node.childNode(withName: "body") as? SKSpriteNode else { return }
            let full = CGFloat(o.y1 - o.y0)
            let until = o.beatsUntilActive(tau)
            let closing = until == 0 ? 1 : max(0, 1 - CGFloat(until) / 0.35)
            body.size.height = max(6, full * closing)
            body.alpha = until == 0 ? 1 : 0.35 + 0.4 * closing
        case .bassWall:
            node.position = CGPoint(x: toScreen(o.x0), y: CGFloat(o.y0))
            if let body = node.childNode(withName: "body") as? SKSpriteNode {
                body.size.height = max(8, CGFloat(o.bassHeight(tau)))
            }
        case .saw:
            let off = o.offset(tau)
            node.position = CGPoint(x: toScreen(o.cx + off.dx), y: CGFloat(o.cy + off.dy))
            node.childNode(withName: "body")?.zRotation = CGFloat(-tau * 9)
        case .pendulum:
            node.position = CGPoint(x: toScreen(o.cx), y: CGFloat(o.cy))
            let b = o.pendulumBall(tau)
            node.childNode(withName: "chain")?.zRotation = CGFloat(b.angle)
            if let ball = node.childNode(withName: "ball") {
                ball.position = CGPoint(x: CGFloat(b.x - o.cx), y: CGFloat(b.y - o.cy))
                ball.zRotation = CGFloat(-tau * 4)
            }
        case .laser:
            placeLaser(node, o, tau: tau, toScreen: toScreen, flash: flash)
        case .pad:
            node.position = CGPoint(x: toScreen(o.x0), y: CGFloat(o.downward ? o.y0 : o.y0))
            node.childNode(withName: "glow")?.alpha = used ? 0.1 : 0.4 + 0.4 * pulse * flash
        case .orb:
            node.position = CGPoint(x: toScreen(o.cx), y: CGFloat(o.cy))
            let s = 1 + 0.12 * pulse
            node.childNode(withName: "body")?.setScale(used ? 0.7 : s)
            node.childNode(withName: "body")?.alpha = used ? 0.35 : 1
            node.childNode(withName: "glow")?.alpha = used ? 0.05 : 0.35 + 0.4 * pulse * flash
        case .portal:
            node.position = CGPoint(x: toScreen(o.x0), y: 0)
            node.childNode(withName: "glow")?.alpha = 0.25 + 0.25 * pulse * flash
            node.childNode(withName: "body")?.xScale = 1 + 0.06 * CGFloat(sin(tau * 9))
        case .speedPortal:
            node.position = CGPoint(x: toScreen(o.x0), y: 0)
            node.childNode(withName: "body")?.alpha = 0.6 + 0.4 * pulse
        }
    }

    private func placeLaser(_ node: SKNode, _ o: CourseObject, tau: Double, toScreen: (Double) -> CGFloat, flash: CGFloat) {
        guard let beam = node.childNode(withName: "beam") as? SKSpriteNode,
              let capA = node.childNode(withName: "capA") as? SKSpriteNode,
              let capB = node.childNode(withName: "capB") as? SKSpriteNode else { return }
        let r = o.rect(tau)
        let x0 = toScreen(r.0), x1 = toScreen(r.1)
        let y0 = CGFloat(r.2), y1 = CGFloat(r.3)
        let horizontal = (x1 - x0) > (y1 - y0)
        node.position = .zero
        let until = o.beatsUntilActive(tau)
        let active = until == 0
        let charge = active ? 1 : max(0, 1 - CGFloat(until) / 0.75) // telegraph in the last 3/4 beat
        let thickness = horizontal ? (y1 - y0) : (x1 - x0)
        let length = horizontal ? (x1 - x0) : (y1 - y0)
        beam.size = CGSize(width: length, height: active ? thickness * 2.4 : max(2, thickness * 0.5 * charge))
        beam.zRotation = horizontal ? 0 : .pi / 2
        beam.position = CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2)
        beam.color = NeonPalette.hazard.uiColor
        beam.colorBlendFactor = active ? 0.25 : 0.8
        beam.alpha = active ? 1 : (0.12 + 0.5 * charge * (0.6 + 0.4 * CGFloat(sin(tau * 60))) * flash)
        capA.size = CGSize(width: 24, height: 24)
        capB.size = CGSize(width: 24, height: 24)
        if horizontal {
            capA.position = CGPoint(x: x0, y: (y0 + y1) / 2)
            capB.position = CGPoint(x: x1, y: (y0 + y1) / 2)
        } else {
            capA.position = CGPoint(x: (x0 + x1) / 2, y: y0)
            capB.position = CGPoint(x: (x0 + x1) / 2, y: y1)
        }
    }
}
