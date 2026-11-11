import AVFoundation
import Foundation

/// Short synthesized sound effects (no audio assets needed). Each character's double jump has
/// its own timbre: Neon Reactor = clean sine, Glitch Pulse = bit-crushed square,
/// Bass Crusher = low saw thump, Prism Drive = bright bell.
enum SoundEffect: Hashable {
    case doubleJump(CharacterSkin.FaceStyle)
    case orb
    case judgmentPerfect
}

enum SoundSynth {
    static func buffer(for effect: SoundEffect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        switch effect {
        case .doubleJump(let style):
            // Two rising notes (a fifth apart) — musical, short, quiet.
            let notes: [(Double, Double)]
            switch style {
            case .reactor: notes = [(880, 0.07), (1318.5, 0.11)]
            case .glitch: notes = [(784, 0.06), (1174.7, 0.1)]
            case .crusher: notes = [(220, 0.08), (330, 0.12)]
            case .prism: notes = [(1046.5, 0.08), (1568, 0.16)]
            }
            let total = notes.reduce(0.0) { $0 + $1.1 }
            return render(format: format, duration: total, sampleRate: sr) { t in
                var start = 0.0
                for (freq, len) in notes {
                    if t >= start && t < start + len {
                        let lt = t - start
                        let env = min(1, lt / 0.004) * exp(-lt * (style == .prism ? 14 : 28))
                        let phase = 2 * Double.pi * freq * lt
                        let v: Double
                        switch style {
                        case .reactor: v = sin(phase) * 0.8 + sin(phase * 2) * 0.2
                        case .glitch:
                            let sq = sin(phase) >= 0 ? 1.0 : -1.0
                            v = (sq * 8).rounded() / 8 * 0.5
                        case .crusher:
                            let saw = 2 * ((freq * lt).truncatingRemainder(dividingBy: 1)) - 1
                            v = saw * 0.6 + sin(2 * Double.pi * 55 * lt) * 0.5
                        case .prism: v = sin(phase) * 0.6 + sin(phase * 2.76) * 0.3 + sin(phase * 5.4) * 0.1
                        }
                        return v * env * 0.35
                    }
                    start += len
                }
                return 0
            }
        case .orb:
            return render(format: format, duration: 0.18, sampleRate: sr) { t in
                sin(2 * Double.pi * 1760 * t) * exp(-t * 20) * 0.25
            }
        case .judgmentPerfect:
            return render(format: format, duration: 0.06, sampleRate: sr) { t in
                sin(2 * Double.pi * 2637 * t) * exp(-t * 60) * 0.15
            }
        }
    }

    private static func render(format: AVAudioFormat, duration: Double, sampleRate sr: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buf.floatChannelData else { return nil }
        buf.frameLength = frames
        let channels = Int(format.channelCount)
        for i in 0..<Int(frames) {
            let v = Float(f(Double(i) / sr))
            for c in 0..<channels { data[c][i] = v }
        }
        return buf
    }
}
