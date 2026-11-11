import SwiftUI

/// A decorative MIDI note used by the menu backdrop.
struct BackdropNote: Sendable {
    let lane: Int
    let beat: Double
    let length: Double
    let velocity: Double

    /// 64 beats (16 bars) of seeded melodic/chordal material that loops.
    static func generate(seed: UInt64 = 0xD20B) -> [BackdropNote] {
        var rng = SeededGenerator(seed: seed)
        var notes: [BackdropNote] = []
        var lane = 10
        var beat = 0.0
        let lengths: [Double] = [0.5, 0.5, 1, 1, 2]
        while beat < 64 {
            lane = min(19, max(9, lane + rng.nextInt(below: 7) - 3))
            let length = lengths[rng.nextInt(below: lengths.count)]
            let velocity = 0.45 + rng.nextDouble() * 0.55
            notes.append(BackdropNote(lane: lane, beat: beat, length: length, velocity: velocity))
            if beat.truncatingRemainder(dividingBy: 4) == 0 {
                // Bar-start chord stab.
                notes.append(BackdropNote(lane: lane - 4, beat: beat, length: 2, velocity: velocity * 0.8))
                notes.append(BackdropNote(lane: lane - 7, beat: beat, length: 2, velocity: velocity * 0.7))
            }
            beat += length
        }
        return notes
    }
}

/// Animated, FL-style piano roll for menus: lanes, beat grid, glowing notes,
/// playhead, velocity lane and an automation curve. Drawn with Canvas.
struct PianoRollBackdrop: View {
    var animated: Bool
    var dimmed: Bool = false
    var bpm: Double = PianoRollMetrics.placeholderBPM

    private static let notes = BackdropNote.generate()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animated)) { timeline in
            Canvas { context, size in
                let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                PianoRollBackdropPainter.draw(in: &context, size: size, time: t, bpm: bpm, notes: Self.notes)
            }
        }
        .overlay {
            if dimmed {
                Color.black.opacity(0.45)
            }
        }
        .accessibilityHidden(true)
    }
}

enum PianoRollBackdropPainter {
    static func draw(in gc: inout GraphicsContext, size: CGSize, time: TimeInterval, bpm: Double, notes: [BackdropNote]) {
        let laneH: CGFloat = 18
        let beatW: CGFloat = 70
        let keyboardW: CGFloat = 36
        let velocityBandH: CGFloat = 44
        let rollBottom = size.height - velocityBandH
        let laneCount = Int((rollBottom / laneH).rounded(.up))
        let pixelsPerSecond = beatW * CGFloat(bpm / 60)
        let scroll = CGFloat(time) * pixelsPerSecond
        let patternWidth = beatW * 64
        let patternScroll = scroll.truncatingRemainder(dividingBy: patternWidth)
        let playheadX = size.width * 0.4

        // Lanes.
        for lane in 0..<laneCount {
            let y = rollBottom - CGFloat(lane + 1) * laneH
            let fill = PianoRollMetrics.isBlackKey(lane: lane) ? NeonPalette.laneBlack : NeonPalette.laneWhite
            gc.fill(Path(CGRect(x: 0, y: y, width: size.width, height: laneH)), with: .color(fill.color))
            gc.fill(Path(CGRect(x: 0, y: y + laneH - 1, width: size.width, height: 1)),
                    with: .color((lane % 12 == 0 ? NeonPalette.beatLine : NeonPalette.laneLine).color))
        }

        // Beat grid.
        let firstBeat = Int((scroll / beatW).rounded(.down))
        let offset = scroll - CGFloat(firstBeat) * beatW
        var x = keyboardW - offset
        var beatIndex = firstBeat
        while x < size.width {
            let isBar = beatIndex % 4 == 0
            gc.fill(Path(CGRect(x: x, y: 0, width: isBar ? 2 : 1, height: rollBottom)),
                    with: .color((isBar ? NeonPalette.barLine : NeonPalette.beatLine).color))
            x += beatW
            beatIndex += 1
        }

        // Notes (with glow) and their velocity bars.
        let noteColorA = NeonPalette.cyan
        let noteColorB = NeonPalette.magenta
        gc.drawLayer { layer in
            layer.addFilter(.shadow(color: NeonPalette.cyan.opacity(0.7), radius: 6))
            for note in notes {
                for wrap in [CGFloat(0), patternWidth] {
                    let nx = keyboardW + CGFloat(note.beat) * beatW - patternScroll + wrap
                    let nw = CGFloat(note.length) * beatW - 3
                    guard nx + nw > keyboardW, nx < size.width else { continue }
                    let lanes = max(laneCount, 1)
                    let lane = ((note.lane % lanes) + lanes) % lanes
                    let ny = rollBottom - CGFloat(lane + 1) * laneH + 1.5
                    let rect = CGRect(x: nx, y: ny, width: nw, height: laneH - 3)
                    let active = nx <= playheadX && nx + nw >= playheadX
                    let base = note.lane.isMultiple(of: 2) ? noteColorA : noteColorB
                    let color = active ? Color.white : base.opacity(0.45 + 0.55 * note.velocity)
                    layer.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))

                    let barH = CGFloat(note.velocity) * (velocityBandH - 10)
                    layer.fill(Path(CGRect(x: nx, y: size.height - barH - 4, width: 3, height: barH)),
                               with: .color(base.opacity(active ? 1 : 0.6)))
                    layer.fill(Path(ellipseIn: CGRect(x: nx - 2.5, y: size.height - barH - 7, width: 8, height: 8)),
                               with: .color(base.opacity(active ? 1 : 0.7)))
                }
            }
        }

        // Velocity band separator.
        gc.fill(Path(CGRect(x: 0, y: rollBottom, width: size.width, height: 1)), with: .color(NeonPalette.barLine.color))

        // Automation curve.
        var curve = Path()
        var px: CGFloat = keyboardW
        while px <= size.width {
            let phase = Double(px + scroll) / 260
            let y = rollBottom * 0.22 + CGFloat(sin(phase) * 26 + sin(phase * 0.37) * 18)
            if px == keyboardW { curve.move(to: CGPoint(x: px, y: y)) } else { curve.addLine(to: CGPoint(x: px, y: y)) }
            px += 8
        }
        gc.stroke(curve, with: .color(NeonPalette.magenta.opacity(0.55)), lineWidth: 1.5)

        // Playhead with beat pulse.
        let beatPhase = (time * bpm / 60).truncatingRemainder(dividingBy: 1)
        let pulse = pow(1 - beatPhase, 3)
        gc.fill(Path(CGRect(x: playheadX - 1, y: 0, width: 2, height: rollBottom)),
                with: .color(NeonPalette.cyan.opacity(0.35 + 0.5 * pulse)))

        // Keyboard.
        gc.fill(Path(CGRect(x: 0, y: 0, width: keyboardW, height: rollBottom)), with: .color(NeonPalette.keyWhite.color))
        for lane in 0..<laneCount {
            let y = rollBottom - CGFloat(lane + 1) * laneH
            if PianoRollMetrics.isBlackKey(lane: lane) {
                gc.fill(Path(CGRect(x: 0, y: y + 2, width: keyboardW * 0.62, height: laneH - 4)),
                        with: .color(NeonPalette.keyBlack.color))
            }
            gc.fill(Path(CGRect(x: 0, y: y + laneH - 1, width: keyboardW, height: 1)),
                    with: .color(.black.opacity(lane % 12 == 0 ? 0.5 : 0.15)))
        }
        gc.fill(Path(CGRect(x: keyboardW - 2, y: 0, width: 2, height: rollBottom)), with: .color(NeonPalette.cyan.opacity(0.8)))
    }
}
