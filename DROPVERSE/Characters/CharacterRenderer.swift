import SwiftUI

/// Facial expressions (overhaul spec §8). Each is baked once per run into a texture and
/// cross-faded at runtime by `PlayerRig`.
enum FaceExpression: String, CaseIterable, Hashable, Sendable {
    case idle, jump, doubleJump, fall, alarm, land, boost, fly, wave, gravity, orb, modeSwitch, celebrate, dead, blink

    /// Shared, skin-independent face parameters; each skin draws them in its own style.
    var params: FaceParams {
        switch self {
        case .idle: return FaceParams(eyeOpen: 1, mouth: 0.6)
        case .blink: return FaceParams(eyeOpen: 0.12, mouth: 0.6)
        case .jump: return FaceParams(eyeOpen: 1.2, lookY: -0.03, mouth: 0.5, mouthOpen: 0.7)
        // Stronger than the first jump: widest eyes, big excited grin.
        case .doubleJump: return FaceParams(eyeOpen: 1.55, lookY: -0.05, brow: -0.3, mouth: 1, mouthOpen: 0.3)
        case .modeSwitch: return FaceParams(eyeOpen: 1.35, lookX: 0.04, brow: 0.4, mouth: 0.4, mouthOpen: 0.55)
        case .fall: return FaceParams(eyeOpen: 1.3, lookY: 0.03, brow: 0.8, mouth: -0.3, mouthOpen: 0.3)
        case .alarm: return FaceParams(eyeOpen: 1.45, brow: 1, mouth: -0.2, mouthOpen: 0.9)
        case .land: return FaceParams(eyeOpen: 0.5, mouth: 1)
        case .boost: return FaceParams(eyeOpen: 0.8, lookX: 0.03, brow: -0.8, mouth: 0.35)
        case .fly: return FaceParams(eyeOpen: 0.9, lookX: 0.035, brow: -0.4, mouth: 0.2)
        case .wave: return FaceParams(eyeOpen: 0.7, lookX: 0.03, brow: -1, mouth: 0.85)
        case .gravity: return FaceParams(eyeOpen: 1.3, lookY: -0.04, brow: 0.6, mouth: 0, mouthOpen: 0.6)
        case .orb: return FaceParams(eyeOpen: 1.1, lookY: -0.03, mouth: 1, mouthOpen: 0.45)
        case .celebrate: return FaceParams(eyeOpen: 0.35, mouth: 1, mouthOpen: 0.6)
        case .dead: return FaceParams(eyeOpen: 1.55, brow: 1, mouth: -1, mouthOpen: 1)
        }
    }
}

struct FaceParams: Equatable {
    var eyeOpen: Double = 1
    var lookX: Double = 0
    var lookY: Double = 0
    /// -1 angry/determined … +1 worried. 0 = no brows (except skins that always show them).
    var brow: Double = 0
    /// -1 frown … +1 smile.
    var mouth: Double = 0.5
    /// 0 closed … 1 wide open.
    var mouthOpen: Double = 0
}

/// Vector rendering of a character portrait.
struct CharacterPortraitView: View {
    let skin: CharacterSkin
    var size: CGFloat = 120
    var expression: FaceExpression = .idle

    var body: some View {
        Canvas { context, canvasSize in
            CharacterPortraitPainter.paint(skin, in: &context, size: canvasSize, expression: expression)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(skin.name))
    }
}

/// Bobbing, blinking, expression-cycling preview used on menus.
struct AnimatedCharacterPortrait: View {
    let skin: CharacterSkin
    var size: CGFloat = 120
    var animated: Bool = true

    private static let showcase: [FaceExpression] = [.idle, .jump, .land, .boost, .gravity, .celebrate]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let bob = animated ? sin(t * 3.2) * 4 : 0
            let tilt = animated ? sin(t * 1.6) * 3 : 0
            let blink = animated && t.truncatingRemainder(dividingBy: 3.4) < 0.12
            let cycle = animated ? Self.showcase[Int(t / 1.7) % Self.showcase.count] : .idle
            CharacterPortraitView(skin: skin, size: size, expression: blink ? .blink : cycle)
                .rotationEffect(.degrees(tilt))
                .offset(y: bob)
        }
    }
}

enum CharacterPortraitPainter {
    static let glowPadding: CGFloat = 0.14

    static func paint(_ skin: CharacterSkin, in gc: inout GraphicsContext, size: CGSize, expression: FaceExpression) {
        let s = min(size.width, size.height)
        let originX = (size.width - s) / 2
        let originY = (size.height - s) / 2
        let pad = s * glowPadding
        let body = CGRect(x: originX + pad, y: originY + pad, width: s - pad * 2, height: s - pad * 2)
        let w = body.width
        let bodyPath = Path(roundedRect: body, cornerRadius: w * 0.14, style: .continuous)
        let face = expression.params

        gc.drawLayer { layer in
            layer.addFilter(.shadow(color: skin.primary.opacity(0.85), radius: s * 0.06))
            layer.fill(bodyPath, with: .color(skin.body.color))
        }
        gc.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [skin.body.color, skin.secondary.opacity(0.3)]),
            startPoint: CGPoint(x: body.minX, y: body.minY),
            endPoint: CGPoint(x: body.maxX, y: body.maxY)))
        gc.stroke(bodyPath, with: .color(skin.primary.color), lineWidth: w * 0.055)
        let inner = body.insetBy(dx: w * 0.1, dy: w * 0.1)
        gc.stroke(Path(roundedRect: inner, cornerRadius: w * 0.08, style: .continuous),
                  with: .color(skin.secondary.opacity(0.7)), lineWidth: w * 0.02)

        paintDetails(skin, &gc, body: body, inner: inner, expression: expression)
        paintEyes(skin, &gc, body: body, face: face)
        paintBrows(skin, &gc, body: body, face: face)
        paintMouth(skin, &gc, body: body, face: face)
    }

    // MARK: - Skin details (unchanged identity from Milestone 1)

    private static func paintDetails(_ skin: CharacterSkin, _ gc: inout GraphicsContext, body: CGRect, inner: CGRect, expression: FaceExpression) {
        let w = body.width
        switch skin.faceStyle {
        case .reactor:
            for x in [body.minX - w * 0.07, body.maxX + w * 0.01] {
                let module = CGRect(x: x, y: body.midY - w * 0.13, width: w * 0.06, height: w * 0.26)
                gc.fill(Path(roundedRect: module, cornerRadius: w * 0.02), with: .color(skin.secondary.color))
            }
            let core = CGRect(x: body.midX - w * 0.05, y: inner.maxY - w * 0.13, width: w * 0.1, height: w * 0.1)
            glowing(&gc, color: skin.secondary.color, radius: w * 0.05) { $0.fill(Path(ellipseIn: core), with: .color(skin.secondary.color)) }
        case .glitch:
            let shift = expression == .dead ? w * 0.12 : w * 0.05
            gc.fill(Path(CGRect(x: body.minX + w * 0.08 + shift, y: body.minY + w * 0.2, width: w * 0.85, height: w * 0.035)),
                    with: .color(skin.secondary.opacity(0.8)))
            gc.fill(Path(CGRect(x: body.minX - shift, y: body.minY + w * 0.82, width: w * 0.6, height: w * 0.03)),
                    with: .color(skin.primary.opacity(0.6)))
        case .crusher:
            for cx in [inner.minX + w * 0.1, inner.maxX - w * 0.1] {
                let c = CGPoint(x: cx, y: inner.maxY - w * 0.09)
                let r = w * 0.07
                gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .color(skin.secondary.color), lineWidth: w * 0.02)
                gc.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45, width: r * 0.9, height: r * 0.9)),
                        with: .color(skin.primary.opacity(0.85)))
            }
            let heights: [CGFloat] = [0.04, 0.08, 0.12, 0.07, 0.05]
            for (i, h) in heights.enumerated() {
                let x = body.midX - w * 0.1 + CGFloat(i) * w * 0.045
                gc.fill(Path(CGRect(x: x, y: inner.minY + w * 0.05 - w * h / 2, width: w * 0.025, height: w * h)),
                        with: .color(skin.secondary.color))
            }
        case .prism:
            var facets = Path()
            let pairs: [(CGPoint, CGPoint)] = [
                (CGPoint(x: body.minX, y: body.minY), CGPoint(x: inner.minX, y: inner.minY)),
                (CGPoint(x: body.maxX, y: body.minY), CGPoint(x: inner.maxX, y: inner.minY)),
                (CGPoint(x: body.minX, y: body.maxY), CGPoint(x: inner.minX, y: inner.maxY)),
                (CGPoint(x: body.maxX, y: body.maxY), CGPoint(x: inner.maxX, y: inner.maxY)),
            ]
            for (a, b) in pairs {
                facets.move(to: a)
                facets.addLine(to: b)
            }
            gc.stroke(facets, with: .color(skin.accent.opacity(0.45)), lineWidth: w * 0.015)
            var highlight = Path()
            highlight.move(to: CGPoint(x: inner.minX, y: inner.minY))
            highlight.addLine(to: CGPoint(x: inner.minX + w * 0.35, y: inner.minY))
            highlight.addLine(to: CGPoint(x: inner.minX, y: inner.minY + w * 0.35))
            highlight.closeSubpath()
            gc.fill(highlight, with: .color(.white.opacity(0.12)))
        }
    }

    // MARK: - Face

    private static func paintEyes(_ skin: CharacterSkin, _ gc: inout GraphicsContext, body: CGRect, face: FaceParams) {
        let w = body.width
        let eyeY = body.minY + w * (0.42 + face.lookY)
        let shiftX = w * face.lookX
        let open = CGFloat(face.eyeOpen)
        let centers = [body.midX - w * 0.17 + shiftX, body.midX + w * 0.17 + shiftX]
        switch skin.faceStyle {
        case .reactor:
            let ew = w * 0.14, eh = max(w * 0.025, w * 0.2 * open)
            glowing(&gc, color: skin.primary.color, radius: w * 0.05) { layer in
                for cx in centers {
                    let r = CGRect(x: cx - ew / 2, y: eyeY - eh / 2, width: ew, height: eh)
                    layer.fill(Path(roundedRect: r, cornerRadius: min(ew, eh) * 0.45), with: .color(skin.accent.color))
                }
            }
        case .glitch:
            let eh = max(w * 0.025, w * 0.19 * open)
            let left = CGRect(x: centers[0] - w * 0.08, y: eyeY - eh * 0.35 + w * 0.02, width: w * 0.16, height: eh * 0.7)
            let right = CGRect(x: centers[1] - w * 0.08, y: eyeY - eh / 2 - w * 0.02, width: w * 0.16, height: eh)
            gc.fill(Path(right.offsetBy(dx: w * 0.035, dy: -w * 0.015)), with: .color(skin.secondary.opacity(0.85)))
            glowing(&gc, color: skin.primary.color, radius: w * 0.05) { layer in
                layer.fill(Path(left), with: .color(skin.primary.color))
                layer.fill(Path(right), with: .color(skin.primary.color))
            }
        case .crusher:
            let eh = max(w * 0.025, w * 0.13 * open)
            glowing(&gc, color: skin.primary.color, radius: w * 0.05) { layer in
                for cx in centers {
                    layer.fill(Path(CGRect(x: cx - w * 0.08, y: eyeY - eh / 2, width: w * 0.16, height: eh)), with: .color(skin.primary.color))
                }
            }
        case .prism:
            let hw = w * 0.08, hh = max(w * 0.015, w * 0.1 * open)
            glowing(&gc, color: skin.secondary.color, radius: w * 0.06) { layer in
                for cx in centers {
                    var eye = Path()
                    eye.move(to: CGPoint(x: cx, y: eyeY - hh))
                    eye.addLine(to: CGPoint(x: cx + hw, y: eyeY))
                    eye.addLine(to: CGPoint(x: cx, y: eyeY + hh))
                    eye.addLine(to: CGPoint(x: cx - hw, y: eyeY))
                    eye.closeSubpath()
                    layer.fill(eye, with: .color(skin.primary.color))
                }
            }
        }
    }

    private static func paintBrows(_ skin: CharacterSkin, _ gc: inout GraphicsContext, body: CGRect, face: FaceParams) {
        let w = body.width
        // Bass Crusher always wears a scowl; others show brows only when the expression needs them.
        let brow = skin.faceStyle == .crusher ? min(face.brow, -0.4) : face.brow
        guard abs(brow) > 0.1 else { return }
        let eyeY = body.minY + w * (0.42 + face.lookY)
        let y = eyeY - w * 0.16
        let tilt = w * 0.06 * CGFloat(brow) // + worried (outer low), - angry (inner low)
        var p = Path()
        p.move(to: CGPoint(x: body.midX - w * 0.29, y: y + tilt))
        p.addLine(to: CGPoint(x: body.midX - w * 0.08, y: y - tilt))
        p.move(to: CGPoint(x: body.midX + w * 0.29, y: y + tilt))
        p.addLine(to: CGPoint(x: body.midX + w * 0.08, y: y - tilt))
        gc.stroke(p, with: .color(skin.accent.color), style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round))
    }

    private static func paintMouth(_ skin: CharacterSkin, _ gc: inout GraphicsContext, body: CGRect, face: FaceParams) {
        let w = body.width
        let mouthY = body.minY + w * 0.64
        let color = skin.faceStyle == .glitch ? skin.primary.color : skin.accent.color
        if face.mouthOpen > 0.35 {
            let mw = w * (0.12 + 0.1 * CGFloat(face.mouthOpen))
            let mh = w * (0.06 + 0.12 * CGFloat(face.mouthOpen))
            let rect = CGRect(x: body.midX - mw / 2, y: mouthY - mh / 2 + w * 0.02, width: mw, height: mh)
            let shape = skin.faceStyle == .crusher ? Path(roundedRect: rect, cornerRadius: mh * 0.2) : Path(ellipseIn: rect)
            gc.fill(shape, with: .color(Color.black.opacity(0.75)))
            gc.stroke(shape, with: .color(color), lineWidth: w * 0.035)
            return
        }
        let curve = CGFloat(face.mouth)
        var p = Path()
        if skin.faceStyle == .glitch && curve > 0.3 {
            // Jagged digital grin.
            p.move(to: CGPoint(x: body.midX - w * 0.2, y: mouthY - w * 0.03))
            for i in 1...6 {
                let x = body.midX - w * 0.2 + CGFloat(i) * (w * 0.41 / 6)
                let y = mouthY + (i.isMultiple(of: 2) ? -w * 0.02 : w * 0.04 * curve) - CGFloat(i) * w * 0.008
                p.addLine(to: CGPoint(x: x, y: y))
            }
        } else {
            let half = w * (skin.faceStyle == .prism ? 0.1 : 0.14)
            let lopsided = skin.faceStyle == .crusher ? w * 0.03 : 0
            p.move(to: CGPoint(x: body.midX - half, y: mouthY + lopsided))
            p.addQuadCurve(to: CGPoint(x: body.midX + half, y: mouthY - lopsided),
                           control: CGPoint(x: body.midX, y: mouthY + w * 0.13 * curve))
        }
        gc.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round, lineJoin: .round))
    }

    static func glowing(_ gc: inout GraphicsContext, color: Color, radius: CGFloat, _ draw: (inout GraphicsContext) -> Void) {
        gc.drawLayer { layer in
            layer.addFilter(.shadow(color: color, radius: radius))
            draw(&layer)
        }
    }
}

/// Skin-specific flight equipment drawn behind the body: Surfer propulsion and Wave fins.
struct PropulsionView: View {
    let skin: CharacterSkin
    let mode: MovementMode
    var size: CGFloat = 140

    var body: some View {
        Canvas { gc, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let u = sz.width / 140 // unit
            if mode == .wave {
                // Swept fins pointing backwards.
                for sign in [CGFloat(-1), 1] {
                    var fin = Path()
                    fin.move(to: CGPoint(x: c.x - 20 * u, y: c.y + sign * 26 * u))
                    fin.addLine(to: CGPoint(x: c.x - 62 * u, y: c.y + sign * 50 * u))
                    fin.addLine(to: CGPoint(x: c.x - 40 * u, y: c.y + sign * 14 * u))
                    fin.closeSubpath()
                    gc.fill(fin, with: .color(skin.secondary.opacity(0.85)))
                    gc.stroke(fin, with: .color(skin.primary.color), lineWidth: 2 * u)
                }
                return
            }
            switch skin.faceStyle {
            case .reactor:
                // Twin energy thrusters.
                for dy in [CGFloat(-18), 18] {
                    let pod = CGRect(x: c.x - 58 * u, y: c.y + dy * u - 9 * u, width: 26 * u, height: 18 * u)
                    gc.fill(Path(roundedRect: pod, cornerRadius: 6 * u), with: .color(skin.secondary.color))
                    var flame = Path()
                    flame.move(to: CGPoint(x: pod.minX, y: pod.minY + 3 * u))
                    flame.addLine(to: CGPoint(x: pod.minX - 22 * u, y: pod.midY))
                    flame.addLine(to: CGPoint(x: pod.minX, y: pod.maxY - 3 * u))
                    CharacterPortraitPainter.glowing(&gc, color: skin.primary.color, radius: 6 * u) {
                        $0.fill(flame, with: .color(skin.primary.color))
                    }
                }
            case .glitch:
                // Distorted pixel wings.
                for sign in [CGFloat(-1), 1] {
                    for i in 0..<5 {
                        let r = CGRect(x: c.x - 40 * u - CGFloat(i) * 9 * u, y: c.y + sign * (30 + CGFloat(i) * 6) * u - 5 * u,
                                       width: 12 * u, height: 10 * u)
                        gc.fill(Path(r), with: .color((i % 2 == 0 ? skin.secondary : skin.primary).opacity(0.9)))
                    }
                }
            case .crusher:
                // Speaker engine with heavy exhaust.
                let cone = CGRect(x: c.x - 66 * u, y: c.y - 26 * u, width: 40 * u, height: 52 * u)
                gc.fill(Path(ellipseIn: cone), with: .color(skin.body.color))
                gc.stroke(Path(ellipseIn: cone), with: .color(skin.primary.color), lineWidth: 3 * u)
                gc.stroke(Path(ellipseIn: cone.insetBy(dx: 10 * u, dy: 13 * u)), with: .color(skin.secondary.color), lineWidth: 2.5 * u)
                var flame = Path()
                flame.move(to: CGPoint(x: cone.minX + 4 * u, y: c.y - 14 * u))
                flame.addLine(to: CGPoint(x: cone.minX - 20 * u, y: c.y))
                flame.addLine(to: CGPoint(x: cone.minX + 4 * u, y: c.y + 14 * u))
                CharacterPortraitPainter.glowing(&gc, color: skin.primary.color, radius: 7 * u) {
                    $0.fill(flame, with: .color(skin.primary.color))
                }
            case .prism:
                // Crystalline wings.
                for sign in [CGFloat(-1), 1] {
                    var wing = Path()
                    wing.move(to: CGPoint(x: c.x - 10 * u, y: c.y + sign * 30 * u))
                    wing.addLine(to: CGPoint(x: c.x - 60 * u, y: c.y + sign * 62 * u))
                    wing.addLine(to: CGPoint(x: c.x - 50 * u, y: c.y + sign * 26 * u))
                    wing.closeSubpath()
                    gc.fill(wing, with: .linearGradient(Gradient(colors: [skin.primary.opacity(0.6), skin.accent.opacity(0.35)]),
                                                        startPoint: c, endPoint: CGPoint(x: c.x - 60 * u, y: c.y)))
                    gc.stroke(wing, with: .color(skin.secondary.color), lineWidth: 1.5 * u)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
