import SpriteKit
import UIKit

/// Chooses the character's expression from gameplay (spec §8) with hold times so faces
/// read clearly instead of flickering.
struct ExpressionController {
    private(set) var current: FaceExpression = .idle
    private var holdUntil: Double = 0
    private var nextBlink: Double = 2.5

    /// Momentary reactions (landing, orb, gravity...) win for a short time.
    mutating func react(_ e: FaceExpression, at t: Double, duration: Double) {
        current = e
        holdUntil = t + duration
    }

    mutating func update(at t: Double, player: PlayerState, nearDanger: Bool, boosting: Bool) -> FaceExpression {
        if player.dead { current = .dead; return current }
        if t < holdUntil { return current }
        let rising = player.vy * player.gravitySign > 80
        let falling = player.vy * player.gravitySign < -260
        let base: FaceExpression
        if nearDanger {
            base = .alarm
        } else {
            switch player.mode {
            case .ship: base = boosting ? .boost : .fly
            case .wave: base = .wave
            case .cube:
                if boosting { base = .boost } else if player.grounded { base = .idle } else if rising { base = .jump } else if falling { base = .fall } else { base = .jump }
            }
        }
        if base == .idle && t >= nextBlink {
            if t < nextBlink + 0.12 { current = .blink; return current }
            nextBlink = t + 2.2 + (t.truncatingRemainder(dividingBy: 1.7))
        }
        current = base
        return current
    }
}

/// The player's visual rig: body (two sprites cross-fading between expression textures),
/// skin-specific propulsion for Surfer/Wave, squash & stretch, gravity flip and mini scale.
final class PlayerRig: SKNode {
    private let bodyA = SKSpriteNode()
    private let bodyB = SKSpriteNode()
    private let propulsion = SKSpriteNode()
    private let aura = SKSpriteNode()
    private let textures: GameTextures
    private let skin: CharacterSkin
    private var shown: FaceExpression = .idle
    private var fade: CGFloat = 1
    private var visualScale: CGFloat = 1
    private var flipScale: CGFloat = 1
    private var spin: CGFloat = 0
    private(set) var squash: CGFloat = 0

    init(textures: GameTextures, skin: CharacterSkin) {
        self.textures = textures
        self.skin = skin
        super.init()
        let side = CGFloat(Sim.halfBig * 2) / 0.72 * 1.08
        for b in [bodyA, bodyB] {
            b.size = CGSize(width: side, height: side)
            b.texture = textures.expressions[.idle]
            addChild(b)
        }
        bodyB.alpha = 0
        bodyA.zPosition = 2
        bodyB.zPosition = 3
        propulsion.size = CGSize(width: side * 1.45, height: side * 1.45)
        propulsion.zPosition = 1
        propulsion.isHidden = true
        addChild(propulsion)
        aura.texture = textures.glowDot
        aura.size = CGSize(width: side * 2.2, height: side * 2.2)
        aura.color = skin.primary.uiColor
        aura.colorBlendFactor = 1
        aura.blendMode = .add
        aura.alpha = 0.35
        aura.zPosition = 0
        addChild(aura)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setExpression(_ e: FaceExpression) {
        guard e != shown, let tex = textures.expressions[e] else { return }
        // Cross-fade: B shows the new face and fades in over ~90 ms; A keeps the old one.
        bodyA.texture = bodyB.alpha > 0.5 ? bodyB.texture : bodyA.texture
        bodyA.alpha = 1
        bodyB.texture = tex
        bodyB.alpha = 0
        fade = 0
        shown = e
    }

    func land() { squash = 1 }

    private var flare: CGFloat = 0

    /// Double jump: a quick extra spin (runner only) and a bright aura flare.
    func doubleJump(reducedMotion: Bool) {
        flare = 1
        if !reducedMotion { spinBoost = CGFloat.pi * 1.5 }
    }

    private var spinBoost: CGFloat = 0

    /// - Parameter dt: real seconds since last frame.
    func update(player: PlayerState, dt: CGFloat, beatPulse: CGFloat, reducedMotion: Bool) {
        if fade < 1 {
            fade = min(1, fade + dt / 0.09)
            bodyB.alpha = fade
            if fade >= 1 {
                bodyA.texture = bodyB.texture
                bodyA.alpha = 1
                bodyB.alpha = 0
            }
        }
        // Size & gravity transitions are animated, never instant.
        let targetScale: CGFloat = player.mini ? CGFloat(Sim.halfMini / Sim.halfBig) : 1
        visualScale += (targetScale - visualScale) * min(1, dt * 14)
        let targetFlip: CGFloat = player.gravitySign < 0 ? -1 : 1
        flipScale += (targetFlip - flipScale) * min(1, dt * 16)

        switch player.mode {
        case .cube:
            propulsion.isHidden = true
            if player.grounded {
                // Snap to the nearest quarter turn smoothly.
                let quarter = CGFloat.pi / 2
                let target = (spin / quarter).rounded() * quarter
                spin += (target - spin) * min(1, dt * 20)
            } else if !reducedMotion {
                spin -= CGFloat(player.gravitySign) * 7.2 * dt
            }
            if spinBoost > 0 {
                let step = min(spinBoost, dt * 22)
                spin -= CGFloat(player.gravitySign) * step
                spinBoost -= step
            }
            zRotation = spin
        case .ship:
            propulsion.isHidden = false
            propulsion.texture = textures.propulsionShip
            let tilt = CGFloat(max(-0.5, min(0.5, player.vy / Sim.shipMax * 0.45)))
            spin += (tilt - spin) * min(1, dt * 12)
            zRotation = spin
        case .wave:
            propulsion.isHidden = false
            propulsion.texture = textures.propulsionWave
            let angle = CGFloat(atan2(player.vy, Sim.speed)) * (player.mini ? 0.9 : 1)
            spin += (angle - spin) * min(1, dt * 25)
            zRotation = spin
        }
        squash = max(0, squash - dt * 5)
        let s = reducedMotion ? 0 : squash * 0.18
        let musical = reducedMotion ? 0 : beatPulse * 0.05
        let modeScale: CGFloat = player.mode == .wave ? 0.8 : 1
        xScale = visualScale * modeScale * (1 + s + musical)
        yScale = visualScale * modeScale * (1 - s + musical) * flipScale
        flare = max(0, flare - dt * 3)
        aura.alpha = 0.25 + 0.35 * beatPulse + 0.6 * flare
        aura.setScale(1 + 0.5 * flare)
    }
}

/// Skin-specific trail: pooled sprites dropped at the player's world position.
final class TrailEmitter {
    private struct Particle {
        let node: SKSpriteNode
        var wx: Double
        var y: CGFloat
        var age: CGFloat
        var life: CGFloat
        var drift: CGFloat
    }

    let layer = SKNode()
    private var pool: [SKSpriteNode] = []
    private var live: [Particle] = []
    private let skin: CharacterSkin
    private let textures: GameTextures
    private var spawnClock: CGFloat = 0
    private var hue: CGFloat = 0
    var intensity: CGFloat = 1

    init(skin: CharacterSkin, textures: GameTextures) {
        self.skin = skin
        self.textures = textures
        for _ in 0..<70 {
            let n = SKSpriteNode(texture: skin.faceStyle == .glitch ? textures.fragment : textures.glowDot)
            n.blendMode = .add
            n.colorBlendFactor = 1
            n.isHidden = true
            layer.addChild(n)
            pool.append(n)
        }
    }

    func reset() {
        for p in live {
            p.node.isHidden = true
            pool.append(p.node)
        }
        live.removeAll(keepingCapacity: true)
    }

    func update(dt: CGFloat, playerWX: Double, playerY: CGFloat, mode: MovementMode, mini: Bool,
                toScreen: (Double) -> CGFloat, alive: Bool) {
        spawnClock += dt
        hue = (hue + dt * 0.6).truncatingRemainder(dividingBy: 1)
        let interval: CGFloat = (mode == .wave ? 0.008 : 0.022) / max(0.3, intensity)
        while alive && spawnClock >= interval {
            spawnClock -= interval
            guard let node = pool.popLast() else { break }
            let base: CGFloat = mini ? 0.6 : 1
            var size: CGFloat
            var life: CGFloat
            var color: UIColor
            switch skin.faceStyle {
            case .reactor:
                size = 16; life = 0.35
                color = (live.count % 2 == 0 ? skin.primary : skin.secondary).uiColor
            case .glitch:
                size = CGFloat.random(in: 6...12); life = 0.3
                color = (Bool.random() ? skin.primary : skin.secondary).uiColor
            case .crusher:
                size = 24; life = 0.4
                color = (Bool.random() ? skin.primary : RGB(hex: 0xFFD23D)).uiColor
            case .prism:
                size = 15; life = 0.45
                color = UIColor(hue: hue, saturation: 0.7, brightness: 1, alpha: 1)
            }
            if mode == .wave { size = 10; life = 0.55 }
            size *= base
            node.size = CGSize(width: size, height: size)
            node.color = color
            node.isHidden = false
            node.alpha = 0.8
            let jitter: CGFloat = skin.faceStyle == .glitch ? CGFloat.random(in: -8...8) : 0
            live.append(Particle(node: node, wx: playerWX - 14, y: playerY + jitter, age: 0, life: life,
                                 drift: skin.faceStyle == .crusher ? CGFloat.random(in: 10...40) : 0))
        }
        var i = 0
        while i < live.count {
            live[i].age += dt
            let p = live[i]
            if p.age >= p.life {
                p.node.isHidden = true
                pool.append(p.node)
                live.swapAt(i, live.count - 1)
                live.removeLast()
                continue
            }
            let k = 1 - p.age / p.life
            p.node.position = CGPoint(x: toScreen(p.wx), y: p.y + p.drift * p.age)
            p.node.alpha = 0.8 * k
            p.node.setScale(0.4 + 0.6 * k)
            i += 1
        }
    }
}
