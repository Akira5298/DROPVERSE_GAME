import SpriteKit
import UIKit

/// Pooled one-shot effects: shockwave rings, particle bursts, screen flashes and camera
/// kicks/shakes. All respect reduced-flash / reduced-motion / camera-shake settings.
final class EffectsLayer {
    let layer = SKNode()
    private var rings: [SKSpriteNode] = []
    private var sparks: [SKSpriteNode] = []
    private let flashNode: SKSpriteNode
    private weak var camera: SKCameraNode?
    private let center: CGPoint
    private let settings: EffectSettings
    private var ringIndex = 0
    private var sparkIndex = 0

    init(size: CGSize, textures: GameTextures, camera: SKCameraNode, settings: EffectSettings) {
        self.camera = camera
        self.settings = settings
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        flashNode = SKSpriteNode(color: .white, size: size)
        flashNode.anchorPoint = .zero
        flashNode.alpha = 0
        flashNode.zPosition = 50
        layer.addChild(flashNode)
        for _ in 0..<8 {
            let r = SKSpriteNode(texture: textures.ring)
            r.blendMode = .add
            r.colorBlendFactor = 1
            r.isHidden = true
            r.zPosition = 20
            layer.addChild(r)
            rings.append(r)
        }
        for _ in 0..<60 {
            let s = SKSpriteNode(texture: textures.fragment)
            s.blendMode = .add
            s.colorBlendFactor = 1
            s.isHidden = true
            s.zPosition = 21
            layer.addChild(s)
            sparks.append(s)
        }
    }

    func reset() {
        for n in rings + sparks {
            n.removeAllActions()
            n.isHidden = true
        }
        flashNode.removeAllActions()
        flashNode.alpha = 0
        camera?.removeAllActions()
        camera?.position = center
        camera?.setScale(1)
    }

    func shockwave(at p: CGPoint, color: UIColor, radius: CGFloat = 160, duration: TimeInterval = 0.45) {
        let r = rings[ringIndex]
        ringIndex = (ringIndex + 1) % rings.count
        r.removeAllActions()
        r.isHidden = false
        r.position = p
        r.color = color
        r.size = CGSize(width: 20, height: 20)
        r.alpha = 0.9
        let scale = radius * 2 / 20
        r.setScale(1)
        r.run(.sequence([
            .group([.scale(to: scale, duration: duration), .fadeOut(withDuration: duration)]),
            .hide(),
        ]))
    }

    func burst(at p: CGPoint, colors: [UIColor], count: Int, speed: ClosedRange<CGFloat> = 80...260, life: TimeInterval = 0.6) {
        let n = max(1, Int(CGFloat(count) * CGFloat(settings.particleIntensity)))
        for i in 0..<n {
            let s = sparks[sparkIndex]
            sparkIndex = (sparkIndex + 1) % sparks.count
            s.removeAllActions()
            s.isHidden = false
            s.position = p
            s.alpha = 1
            let side = CGFloat.random(in: 6...14)
            s.size = CGSize(width: side, height: side)
            s.setScale(1)
            s.color = colors[i % colors.count]
            let a = CGFloat.random(in: 0...(2 * .pi))
            let v = CGFloat.random(in: speed)
            s.run(.sequence([
                .group([
                    .move(by: CGVector(dx: cos(a) * v * CGFloat(life), dy: sin(a) * v * CGFloat(life)), duration: life),
                    .rotate(byAngle: CGFloat.random(in: -6...6), duration: life),
                    .fadeOut(withDuration: life),
                    .scale(to: 0.2, duration: life),
                ]),
                .hide(),
            ]))
        }
    }

    func flash(color: UIColor, peak: CGFloat, duration: TimeInterval) {
        let alpha = settings.reducedFlashing ? min(peak, 0.08) : peak
        guard alpha > 0.01 else { return }
        flashNode.removeAllActions()
        flashNode.color = color
        flashNode.alpha = 0
        flashNode.run(.sequence([.fadeAlpha(to: alpha, duration: duration * 0.2), .fadeOut(withDuration: duration * 0.8)]))
    }

    /// Short zoom "kick" on strong beats.
    func kick(strength: CGFloat) {
        guard !settings.reducedMotion, let camera else { return }
        let amount = 1 - 0.012 * strength
        camera.removeAction(forKey: "kick")
        camera.run(.sequence([.scale(to: amount, duration: 0.04), .scale(to: 1, duration: 0.18)]), withKey: "kick")
    }

    func shake(intensity: CGFloat) {
        let amount = CGFloat(settings.cameraShake) * 14 * intensity
        guard amount > 0.5, !settings.reducedMotion, let camera else { return }
        var actions: [SKAction] = []
        for i in 0..<6 {
            let falloff = 1 - CGFloat(i) / 6
            actions.append(.move(to: CGPoint(x: center.x + CGFloat.random(in: -1...1) * amount * falloff,
                                             y: center.y + CGFloat.random(in: -1...1) * amount * falloff), duration: 0.035))
        }
        actions.append(.move(to: center, duration: 0.05))
        camera.removeAction(forKey: "shake")
        camera.run(.sequence(actions), withKey: "shake")
    }
}

/// Visual-effect preferences the scene must respect (accessibility).
struct EffectSettings: Equatable {
    var reducedMotion: Bool
    var reducedFlashing: Bool
    var cameraShake: Double
    var particleIntensity: Double

    init(settings: GameSettings) {
        reducedMotion = settings.reducedMotion
        reducedFlashing = settings.reducedFlashing
        cameraShake = settings.reducedMotion ? 0 : settings.cameraShake
        particleIntensity = settings.particleIntensity.multiplier
    }
}
