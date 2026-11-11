import SpriteKit
import UIKit

/// Developer overlay that draws the *simulation's* collision geometry (not the sprites):
/// player hitbox, supports, hazard cores, pits and triggers. If a sprite and its outline
/// disagree, that mismatch is the bug.
final class DebugBoundsRenderer {
    let layer = SKNode()
    private var pool: [SKShapeNode] = []
    private var used = 0

    init() {
        layer.zPosition = 45
        layer.isHidden = true
    }

    var enabled: Bool {
        get { !layer.isHidden }
        set { layer.isHidden = !newValue }
    }

    private func next() -> SKShapeNode {
        if used < pool.count {
            let n = pool[used]
            used += 1
            n.isHidden = false
            return n
        }
        let n = SKShapeNode()
        n.lineWidth = 1.5
        n.fillColor = .clear
        layer.addChild(n)
        pool.append(n)
        used += 1
        return n
    }

    private func rect(_ r: CGRect, _ color: UIColor) {
        let n = next()
        n.path = CGPath(rect: r, transform: nil)
        n.strokeColor = color
    }

    private func circle(_ c: CGPoint, _ radius: CGFloat, _ color: UIColor) {
        let n = next()
        n.path = CGPath(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        n.strokeColor = color
    }

    func update(course: Course, player: PlayerState, tau: Double, playerScreenX: CGFloat, playerWX: Double, viewWidth: CGFloat) {
        used = 0
        defer { for i in used..<pool.count { pool[i].isHidden = true } }
        guard enabled else { return }
        let toScreen: (Double) -> CGFloat = { playerScreenX + CGFloat($0 - playerWX) }
        let minX = playerWX - Double(playerScreenX) - 50
        let maxX = playerWX + Double(viewWidth - playerScreenX) + 50
        let h = CGFloat(player.half)
        rect(CGRect(x: playerScreenX - h, y: CGFloat(player.y) - h, width: h * 2, height: h * 2), .green)
        for seg in course.floorSegments where seg.1 >= minX && seg.0 <= maxX {
            let a = toScreen(max(seg.0, minX)), b = toScreen(min(seg.1, maxX))
            rect(CGRect(x: a, y: CGFloat(Sim.floorY) - 6, width: b - a, height: 6), .cyan)
        }
        var i = course.firstIndex(minXAtLeast: minX - Course.maxObjectSpan)
        while i < course.objects.count && used < 220 {
            let o = course.objects[i]
            i += 1
            if o.minX > maxX { break }
            if o.maxX < minX { continue }
            switch o.kind {
            case .pit:
                rect(CGRect(x: toScreen(o.x0), y: 0, width: CGFloat(o.x1 - o.x0), height: CGFloat(Sim.floorY)), .yellow)
            case .spike:
                let off = o.offset(tau)
                for k in 0..<o.count {
                    let cx = o.x0 + Sim.spikeWidth / 2 + Double(k) * Sim.spikeWidth + off.dx
                    let base = o.y0 + off.dy
                    let y0 = o.downward ? base - Sim.spikeCoreHeight : base
                    rect(CGRect(x: toScreen(cx - Sim.spikeCoreHalf), y: CGFloat(y0), width: CGFloat(Sim.spikeCoreHalf * 2),
                                height: CGFloat(Sim.spikeCoreHeight)), .red)
                }
            case .saw:
                let off = o.offset(tau)
                circle(CGPoint(x: toScreen(o.cx + off.dx), y: CGFloat(o.cy + off.dy)), CGFloat(o.collisionRadius), .red)
            case .pendulum:
                let b = o.pendulumBall(tau)
                circle(CGPoint(x: toScreen(b.x), y: CGFloat(b.y)), CGFloat(o.collisionRadius), .red)
            case .laser, .gate:
                let r = o.rect(tau)
                rect(CGRect(x: toScreen(r.0), y: CGFloat(r.2), width: CGFloat(r.1 - r.0), height: CGFloat(r.3 - r.2)),
                     o.isActive(tau) ? .red : UIColor.red.withAlphaComponent(0.25))
            case .bassWall:
                rect(CGRect(x: toScreen(o.x0), y: CGFloat(o.y0), width: CGFloat(o.x1 - o.x0), height: CGFloat(o.bassHeight(tau))), .red)
            case .hazardBlock, .noteHazard:
                let r = o.rect(tau)
                rect(CGRect(x: toScreen(r.0), y: CGFloat(r.2), width: CGFloat(r.1 - r.0), height: CGFloat(r.3 - r.2)), .red)
            case .block, .noteBlock, .pillar, .movingBlock, .fallingPlatform:
                let r = o.rect(tau)
                rect(CGRect(x: toScreen(r.0), y: CGFloat(r.2), width: CGFloat(r.1 - r.0), height: CGFloat(r.3 - r.2)),
                     o.id == player.supportID ? .green : .cyan)
            case .orb:
                circle(CGPoint(x: toScreen(o.cx), y: CGFloat(o.cy)), CGFloat(o.collisionRadius), .white)
            case .pad:
                rect(CGRect(x: toScreen(o.x0), y: CGFloat(o.y0), width: CGFloat(o.x1 - o.x0), height: CGFloat(o.y1 - o.y0)), .white)
            case .portal, .speedPortal:
                rect(CGRect(x: toScreen(o.x0) - 1, y: CGFloat(Sim.floorY), width: 2, height: CGFloat(Sim.playHeight)), .white)
            }
        }
    }
}
