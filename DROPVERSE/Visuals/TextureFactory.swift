import SpriteKit
import SwiftUI
import UIKit

/// All textures a run needs, generated once (no per-frame allocation). Treated as an atlas:
/// every sprite of one kind shares one texture, so SpriteKit batches draws.
struct GameTextures {
    let expressions: [FaceExpression: SKTexture]
    let propulsionShip: SKTexture?
    let propulsionWave: SKTexture?
    let spike: SKTexture
    let block: SKTexture
    let noteBlock: SKTexture
    let fallingPlatform: SKTexture
    let dashedLine: SKTexture
    let dottedLine: SKTexture
    let pillar: SKTexture
    let hazardBlock: SKTexture
    let noteHazard: SKTexture
    let saw: SKTexture
    let spikedBall: SKTexture
    let laserBeam: SKTexture
    let emitter: SKTexture
    let gate: SKTexture
    let bassWall: SKTexture
    let pad: SKTexture
    let orb: SKTexture
    let portals: [PortalKind: SKTexture]
    let speedPortal: SKTexture
    let ring: SKTexture
    let glowDot: SKTexture
    let fragment: SKTexture
    let lanesTile: SKTexture
    let keyboard: SKTexture
    let sequencerPanel: SKTexture
    let decoNote: SKTexture

    /// 9-slice insets (normalized) for stretchable textures.
    static let blockCenter = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    static let noteCenter = CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4)
}

@MainActor
enum TextureFactory {
    static func makeGameTextures(skin: CharacterSkin, sceneHeight: CGFloat) -> GameTextures {
        var expressions: [FaceExpression: SKTexture] = [:]
        for expression in FaceExpression.allCases {
            if let t = portrait(skin: skin, expression: expression) { expressions[expression] = t }
        }
        var portals: [PortalKind: SKTexture] = [:]
        for kind in [PortalKind.cube, .ship, .wave, .gravityFlip, .gravityNormal, .mini, .big] {
            portals[kind] = portalTexture(kind)
        }
        return GameTextures(
            expressions: expressions,
            propulsionShip: propulsion(skin: skin, mode: .ship),
            propulsionWave: propulsion(skin: skin, mode: .wave),
            spike: spikeTexture(),
            block: blockTexture(fill: WorldTheme.safeDark, edge: WorldTheme.safe, grid: true),
            noteBlock: noteTexture(color: WorldTheme.safe, hazard: false),
            fallingPlatform: fallingPlatformTexture(),
            dashedLine: dashTexture(dash: 10, gap: 8),
            dottedLine: dashTexture(dash: 3, gap: 9),
            pillar: blockTexture(fill: RGB(hex: 0x0A1A22), edge: RGB(hex: 0x1FB89A), grid: false),
            hazardBlock: hazardBlockTexture(),
            noteHazard: noteTexture(color: NeonPalette.hazard, hazard: true),
            saw: sawTexture(),
            spikedBall: spikedBallTexture(),
            laserBeam: beamTexture(),
            emitter: emitterTexture(),
            gate: gateTexture(),
            bassWall: bassWallTexture(),
            pad: padTexture(),
            orb: orbTexture(),
            portals: portals,
            speedPortal: speedPortalTexture(),
            ring: ringTexture(),
            glowDot: glowDotTexture(),
            fragment: fragmentTexture(),
            lanesTile: lanesTileTexture(height: sceneHeight),
            keyboard: keyboardTexture(height: sceneHeight),
            sequencerPanel: sequencerPanelTexture(),
            decoNote: decoNoteTexture())
    }

    // MARK: - Character

    static func portrait(skin: CharacterSkin, expression: FaceExpression) -> SKTexture? {
        let renderer = ImageRenderer(content: CharacterPortraitView(skin: skin, size: 96, expression: expression))
        renderer.scale = 2.5
        guard let image = renderer.uiImage else { return nil }
        return SKTexture(image: image)
    }

    static func propulsion(skin: CharacterSkin, mode: MovementMode) -> SKTexture? {
        let renderer = ImageRenderer(content: PropulsionView(skin: skin, mode: mode, size: 140))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return SKTexture(image: image)
    }

    // MARK: - Hazards (red/magenta family, spiky or striped)

    static func spikeTexture() -> SKTexture {
        let w = CGFloat(Sim.spikeWidth), h = CGFloat(Sim.spikeWidth), pad = spikePad
        let size = CGSize(width: w + pad * 2, height: h + pad * 2)
        return texture(size: size, scale: 3) { ctx, _ in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: pad, y: size.height - pad))
            path.addLine(to: CGPoint(x: pad + w, y: size.height - pad))
            path.addLine(to: CGPoint(x: pad + w / 2, y: pad))
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 9, color: NeonPalette.hazard.uiColor.cgColor)
            ctx.addPath(path)
            ctx.setFillColor(NeonPalette.hazardDark.uiColor.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            fillVerticalGradient(ctx, top: NeonPalette.hazard.uiColor(alpha: 0.7), bottom: NeonPalette.hazardDark.uiColor,
                                 rect: CGRect(x: 0, y: pad, width: size.width, height: h))
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.setLineWidth(3)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    /// Plain constant, read by the renderer off the main actor.
    nonisolated static let spikePad: CGFloat = 10

    static func hazardBlockTexture() -> SKTexture {
        let size = CGSize(width: 64, height: 64)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.setFillColor(NeonPalette.hazardDark.uiColor.cgColor)
            ctx.fill(rect)
            ctx.saveGState()
            ctx.clip(to: rect.insetBy(dx: 4, dy: 4))
            ctx.setStrokeColor(NeonPalette.hazard.uiColor(alpha: 0.55).cgColor)
            ctx.setLineWidth(6)
            var x: CGFloat = -64
            while x < 64 {
                ctx.move(to: CGPoint(x: x, y: 64))
                ctx.addLine(to: CGPoint(x: x + 64, y: 0))
                x += 16
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.setStrokeColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.setLineWidth(4)
            ctx.stroke(rect.insetBy(dx: 2, dy: 2))
        }
    }

    static func sawTexture() -> SKTexture {
        let size = CGSize(width: 96, height: 96)
        return texture(size: size, scale: 2) { ctx, rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let teeth = 14
            let path = CGMutablePath()
            for i in 0..<(teeth * 2) {
                let a = CGFloat(i) / CGFloat(teeth * 2) * .pi * 2
                let r: CGFloat = i % 2 == 0 ? 46 : 36
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6, color: NeonPalette.hazard.uiColor.cgColor)
            ctx.addPath(path)
            ctx.setFillColor(RGB(hex: 0x3A0A1A).uiColor.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokePath()
            ctx.setStrokeColor(NeonPalette.orange.uiColor(alpha: 0.8).cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40))
            ctx.setFillColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                ctx.move(to: CGPoint(x: c.x + cos(a) * 9, y: c.y + sin(a) * 9))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * 30, y: c.y + sin(a) * 30))
            }
            ctx.setStrokeColor(NeonPalette.orange.uiColor(alpha: 0.6).cgColor)
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
    }

    static func spikedBallTexture() -> SKTexture {
        let size = CGSize(width: 84, height: 84)
        return texture(size: size, scale: 2) { ctx, rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let path = CGMutablePath()
            let n = 10
            for i in 0..<(n * 2) {
                let a = CGFloat(i) / CGFloat(n * 2) * .pi * 2
                let r: CGFloat = i % 2 == 0 ? 40 : 27
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: NeonPalette.magenta.uiColor.cgColor)
            ctx.addPath(path)
            ctx.setFillColor(RGB(hex: 0x2A0626).uiColor.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokePath()
            ctx.setFillColor(NeonPalette.magenta.uiColor(alpha: 0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
        }
    }

    static func noteTexture(color: RGB, hazard: Bool) -> SKTexture {
        let size = CGSize(width: 64, height: 40)
        return texture(size: size, scale: 2) { ctx, rect in
            let body = rect.insetBy(dx: 3, dy: hazard ? 8 : 4)
            let path = CGPath(roundedRect: body, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 7, color: color.uiColor.cgColor)
            ctx.addPath(path)
            ctx.setFillColor(color.uiColor(alpha: hazard ? 0.35 : 0.45).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(color.uiColor.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokePath()
            if hazard {
                // Zigzag teeth top and bottom: unmistakably dangerous.
                ctx.setFillColor(color.uiColor.cgColor)
                var x: CGFloat = 4
                while x < 60 {
                    ctx.move(to: CGPoint(x: x, y: 8))
                    ctx.addLine(to: CGPoint(x: x + 4, y: 1))
                    ctx.addLine(to: CGPoint(x: x + 8, y: 8))
                    ctx.move(to: CGPoint(x: x, y: 32))
                    ctx.addLine(to: CGPoint(x: x + 4, y: 39))
                    ctx.addLine(to: CGPoint(x: x + 8, y: 32))
                    x += 8
                }
                ctx.fillPath()
            } else {
                // Velocity notch + top highlight: a MIDI note you can stand on.
                ctx.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
                ctx.fill(CGRect(x: body.minX + 4, y: body.minY + 3, width: body.width - 8, height: 3))
                ctx.setFillColor(color.uiColor.cgColor)
                ctx.fill(CGRect(x: body.minX + 3, y: body.minY + 3, width: 5, height: body.height - 6))
            }
        }
    }

    // MARK: - Safe surfaces

    /// Safe (standable) but temporary: amber note with cracks.
    static func fallingPlatformTexture() -> SKTexture {
        let size = CGSize(width: 64, height: 40)
        let amber = RGB(hex: 0xFFB13D)
        return texture(size: size, scale: 2) { ctx, rect in
            let body = rect.insetBy(dx: 3, dy: 4)
            let path = CGPath(roundedRect: body, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6, color: amber.uiColor.cgColor)
            ctx.addPath(path)
            ctx.setFillColor(amber.uiColor(alpha: 0.4).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(amber.uiColor.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokePath()
            ctx.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
            ctx.fill(CGRect(x: body.minX + 4, y: body.minY + 3, width: body.width - 8, height: 3))
            ctx.setStrokeColor(UIColor(white: 0, alpha: 0.6).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 22, y: 8)); ctx.addLine(to: CGPoint(x: 27, y: 20)); ctx.addLine(to: CGPoint(x: 22, y: 32))
            ctx.move(to: CGPoint(x: 42, y: 8)); ctx.addLine(to: CGPoint(x: 38, y: 19)); ctx.addLine(to: CGPoint(x: 44, y: 32))
            ctx.strokePath()
        }
    }

    /// Vertical dashed/dotted line tile (white, tinted at runtime) for the rhythm guide grid.
    static func dashTexture(dash: CGFloat, gap: CGFloat) -> SKTexture {
        let height: CGFloat = 450
        return texture(size: CGSize(width: 4, height: height), scale: 2) { ctx, _ in
            ctx.setFillColor(UIColor.white.cgColor)
            var y: CGFloat = 0
            while y < height {
                ctx.fill(CGRect(x: 1, y: y, width: 2, height: dash))
                y += dash + gap
            }
        }
    }

    static func blockTexture(fill: RGB, edge: RGB, grid: Bool) -> SKTexture {
        let size = CGSize(width: 64, height: 64)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.setFillColor(fill.uiColor.cgColor)
            ctx.fill(rect)
            if grid {
                ctx.setStrokeColor(edge.uiColor(alpha: 0.18).cgColor)
                ctx.setLineWidth(1)
                for i in 1..<4 {
                    let v = CGFloat(i) * 16
                    ctx.move(to: CGPoint(x: v, y: 0)); ctx.addLine(to: CGPoint(x: v, y: 64))
                    ctx.move(to: CGPoint(x: 0, y: v)); ctx.addLine(to: CGPoint(x: 64, y: v))
                }
                ctx.strokePath()
            }
            ctx.setStrokeColor(edge.uiColor.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(rect.insetBy(dx: 1.5, dy: 1.5))
            // Bright standable top edge.
            ctx.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            ctx.fill(CGRect(x: 3, y: 3, width: 58, height: 2))
        }
    }

    // MARK: - Music-reactive

    static func beamTexture() -> SKTexture {
        let size = CGSize(width: 8, height: 32)
        return texture(size: size, scale: 2) { ctx, rect in
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.9).cgColor,
                          UIColor.white.cgColor, UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.5, 0.65, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: rect.height), options: [])
            }
        }
    }

    static func emitterTexture() -> SKTexture {
        let size = CGSize(width: 28, height: 28)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.setFillColor(RGB(hex: 0x1A1024).uiColor.cgColor)
            ctx.fill(rect.insetBy(dx: 2, dy: 2))
            ctx.setStrokeColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.setLineWidth(2.5)
            ctx.stroke(rect.insetBy(dx: 3, dy: 3))
            ctx.setFillColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 9, dy: 9))
        }
    }

    static func gateTexture() -> SKTexture {
        let size = CGSize(width: 32, height: 64)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.setFillColor(RGB(hex: 0x2A0A2E).uiColor.cgColor)
            ctx.fill(rect)
            ctx.setFillColor(NeonPalette.magenta.uiColor(alpha: 0.55).cgColor)
            var y: CGFloat = 4
            while y < 64 {
                ctx.fill(CGRect(x: 4, y: y, width: 24, height: 4))
                y += 10
            }
            ctx.setStrokeColor(NeonPalette.magenta.uiColor.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(rect.insetBy(dx: 1.5, dy: 1.5))
        }
    }

    static func bassWallTexture() -> SKTexture {
        let size = CGSize(width: 32, height: 64)
        return texture(size: size, scale: 2) { ctx, rect in
            fillVerticalGradient(ctx, top: NeonPalette.hazard.uiColor, bottom: RGB(hex: 0x3A0A16).uiColor, rect: rect)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 4))
            ctx.setStrokeColor(NeonPalette.hazard.uiColor.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 1, dy: 1))
        }
    }

    // MARK: - Interactives (white, tinted at runtime)

    static func padTexture() -> SKTexture {
        let size = CGSize(width: 48, height: 20)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6, color: UIColor.white.cgColor)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: 4, y: 6, width: 40, height: 24))
            ctx.restoreGState()
            ctx.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            ctx.fill(CGRect(x: 0, y: 16, width: 48, height: 4))
        }
    }

    static func orbTexture() -> SKTexture {
        let size = CGSize(width: 72, height: 72)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: UIColor.white.cgColor)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(6)
            ctx.strokeEllipse(in: rect.insetBy(dx: 10, dy: 10))
            ctx.restoreGState()
            ctx.setFillColor(UIColor(white: 1, alpha: 0.5).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 26, dy: 26))
        }
    }

    static func portalTexture(_ kind: PortalKind) -> SKTexture {
        let size = CGSize(width: 74, height: 460)
        let (color, label): (RGB, String) = {
            switch kind {
            case .cube: return (NeonPalette.lime, "CUBE")
            case .ship: return (NeonPalette.magenta, "SURF")
            case .wave: return (NeonPalette.cyan, "WAVE")
            case .gravityFlip: return (RGB(hex: 0xFFD23D), "G ▲")
            case .gravityNormal: return (RGB(hex: 0x3D9BFF), "G ▼")
            case .mini: return (RGB(hex: 0xFF6BD8), "MINI")
            case .big: return (RGB(hex: 0x6BFF9E), "BIG")
            }
        }()
        return texture(size: size, scale: 2) { ctx, rect in
            let ring = rect.insetBy(dx: 10, dy: 8)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10, color: color.uiColor.cgColor)
            ctx.setStrokeColor(color.uiColor.cgColor)
            ctx.setLineWidth(7)
            ctx.strokeEllipse(in: ring)
            ctx.restoreGState()
            ctx.setFillColor(color.uiColor(alpha: 0.12).cgColor)
            ctx.fillEllipse(in: ring.insetBy(dx: 6, dy: 6))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .black),
                .foregroundColor: UIColor.white,
            ]
            for (i, ch) in label.enumerated() {
                let s = String(ch) as NSString
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - CGFloat(label.count) * 9 + CGFloat(i) * 18),
                       withAttributes: attrs)
            }
        }
    }

    static func speedPortalTexture() -> SKTexture {
        let size = CGSize(width: 80, height: 200)
        return texture(size: size, scale: 2) { ctx, rect in
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(7)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for i in 0..<3 {
                let x = 14 + CGFloat(i) * 20
                ctx.move(to: CGPoint(x: x, y: 40))
                ctx.addLine(to: CGPoint(x: x + 18, y: rect.midY))
                ctx.addLine(to: CGPoint(x: x, y: 160))
            }
            ctx.strokePath()
        }
    }

    // MARK: - Effects

    static func ringTexture() -> SKTexture {
        texture(size: CGSize(width: 128, height: 128), scale: 2) { ctx, rect in
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(5)
            ctx.strokeEllipse(in: rect.insetBy(dx: 6, dy: 6))
        }
    }

    static func glowDotTexture() -> SKTexture {
        texture(size: CGSize(width: 32, height: 32), scale: 2) { ctx, rect in
            let colors = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                       endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
            }
        }
    }

    static func fragmentTexture() -> SKTexture {
        texture(size: CGSize(width: 16, height: 16), scale: 2) { ctx, rect in
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - DAW world

    /// Pitch lanes only (vertical grid lines are separate sprites placed on the beat).
    static func lanesTileTexture(height: CGFloat) -> SKTexture {
        let size = CGSize(width: 64, height: height)
        return texture(size: size, scale: 1) { ctx, _ in
            let laneHeight = PianoRollMetrics.laneHeight
            let count = Int((height / laneHeight).rounded(.up))
            for lane in 0..<count {
                let y = height - CGFloat(lane + 1) * laneHeight
                let fill = PianoRollMetrics.isBlackKey(lane: lane) ? NeonPalette.laneBlack : NeonPalette.laneWhite
                ctx.setFillColor(fill.uiColor.cgColor)
                ctx.fill(CGRect(x: 0, y: y, width: 64, height: laneHeight))
                ctx.setFillColor((lane % 12 == 0 ? NeonPalette.beatLine : NeonPalette.laneLine).uiColor.cgColor)
                ctx.fill(CGRect(x: 0, y: y + laneHeight - 1, width: 64, height: 1))
            }
        }
    }

    /// Fixed keyboard strip with track-lane labels.
    static func keyboardTexture(height: CGFloat) -> SKTexture {
        let width: CGFloat = 92
        let keyW = PianoRollMetrics.keyboardWidth
        let size = CGSize(width: width, height: height)
        return texture(size: size, scale: 2) { ctx, _ in
            ctx.setFillColor(RGB(hex: 0x0A0F1E).uiColor(alpha: 0.92).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width - keyW, height: height))
            let laneHeight = PianoRollMetrics.laneHeight
            let count = Int((height / laneHeight).rounded(.up))
            ctx.setFillColor(NeonPalette.keyWhite.uiColor.cgColor)
            ctx.fill(CGRect(x: width - keyW, y: 0, width: keyW, height: height))
            for lane in 0..<count {
                let y = height - CGFloat(lane + 1) * laneHeight
                if PianoRollMetrics.isBlackKey(lane: lane) {
                    ctx.setFillColor(NeonPalette.keyBlack.uiColor.cgColor)
                    ctx.fill(CGRect(x: width - keyW, y: y + 2, width: keyW * 0.62, height: laneHeight - 4))
                }
                ctx.setFillColor(UIColor(white: 0, alpha: lane % 12 == 0 ? 0.55 : 0.18).cgColor)
                ctx.fill(CGRect(x: width - keyW, y: y + laneHeight - 1, width: keyW, height: 1))
            }
            // Track lane labels, each spanning a group of lanes.
            let labels = ["KICK", "SNARE", "BASS", "LEAD", "CHORD", "PAD", "FX", "VOX"]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NeonPalette.textSecondary.uiColor,
            ]
            let groupH = height / CGFloat(labels.count)
            for (i, label) in labels.enumerated() {
                let yTop = height - CGFloat(i + 1) * groupH
                ctx.setFillColor(PianoRollMetrics.stageTints[i % PianoRollMetrics.stageTints.count].uiColor.cgColor)
                ctx.fill(CGRect(x: 3, y: yTop + 4, width: 3, height: groupH - 8))
                (label as NSString).draw(at: CGPoint(x: 9, y: yTop + groupH / 2 - 7), withAttributes: attrs)
            }
            ctx.setFillColor(NeonPalette.cyan.uiColor(alpha: 0.8).cgColor)
            ctx.fill(CGRect(x: width - 2, y: 0, width: 2, height: height))
        }
    }

    static func sequencerPanelTexture() -> SKTexture {
        let size = CGSize(width: 320, height: 96)
        return texture(size: size, scale: 2) { ctx, rect in
            let panel = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 10, cornerHeight: 10, transform: nil)
            ctx.addPath(panel)
            ctx.setFillColor(RGB(hex: 0x10183A).uiColor(alpha: 0.55).cgColor)
            ctx.fillPath()
            ctx.addPath(panel)
            ctx.setStrokeColor(NeonPalette.cyan.uiColor(alpha: 0.5).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
            for row in 0..<3 {
                for step in 0..<16 {
                    let x = 12 + CGFloat(step) * 18.5
                    let y = 14 + CGFloat(row) * 24
                    let on = (step + row * 3) % (row + 3) == 0
                    ctx.setFillColor((on ? NeonPalette.magenta.uiColor(alpha: 0.65) : UIColor(white: 1, alpha: 0.08)).cgColor)
                    ctx.fill(CGRect(x: x, y: y, width: 14, height: 16))
                }
            }
        }
    }

    static func decoNoteTexture() -> SKTexture {
        texture(size: CGSize(width: 32, height: 16), scale: 2) { ctx, rect in
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 2), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - Helpers

    private static func fillVerticalGradient(_ ctx: CGContext, top: UIColor, bottom: UIColor, rect: CGRect) {
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
    }

    private static func texture(size: CGSize, scale: CGFloat, _ draw: (CGContext, CGRect) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }
}
