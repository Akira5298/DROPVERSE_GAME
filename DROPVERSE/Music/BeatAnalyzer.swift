import Accelerate
import AVFoundation
import Foundation

/// Result of analysing one track. Cached as JSON so analysis runs once per file.
struct TrackAnalysis: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var version: Int
    var bpm: Double
    /// Time of the first detected downbeat (seconds).
    var firstDownbeat: Double
    var duration: Double
    var dropStart: Double
    var dropEnd: Double
    /// Bars in the drop segment.
    var dropBars: Int
    /// Mean energy per bar inside the drop, normalised 0...1.
    var barEnergy: [Double]
    /// Strength of the winning tempo hypothesis relative to the average (higher = surer).
    var tempoConfidence: Double
    /// True when bpm / drop came from tracks.json instead of detection.
    var manual: Bool

    var beatDuration: Double { 60 / bpm }
    var dropDuration: Double { dropEnd - dropStart }
}

enum AnalysisError: Error, LocalizedError {
    case unreadable(String)
    case tooShort

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "Audio could not be read: \(reason)"
        case .tooShort: return "Track is too short for a 20-second drop."
        }
    }
}

/// Offline tempo, downbeat and drop detection (spec §19).
///
/// Pipeline: decode → mono, ~11 kHz → per-hop energy (full band + low band via a one-pole
/// low-pass) using vDSP → log-energy flux onset envelope → autocorrelation tempo estimate
/// (45–180 BPM) → comb-filter refinement of BPM and beat phase → downbeat choice from
/// energy jumps → drop window that maximises bar energy and the energy jump into it.
/// Results are cached; tracks.json values override detection when supplied.
enum BeatAnalyzer {
    static let targetRate = 11_025.0
    static let hop = 128
    static let minDrop = 20.0
    static let maxDrop = 45.0
    static let idealDrop = 30.0

    static func analyze(track: Track) throws -> TrackAnalysis {
        let (envFull, envLow, envRate, duration) = try energyEnvelopes(url: track.url)
        guard duration >= 8 else { throw AnalysisError.tooShort }
        let onset = onsetEnvelope(full: envFull, low: envLow)

        var bpm: Double
        var phaseFrames: Double
        var confidence: Double
        if let manual = track.manualBPM, manual > 0 {
            bpm = manual
            (phaseFrames, confidence) = bestPhase(onset: onset, rate: envRate, bpm: manual)
        } else {
            (bpm, phaseFrames, confidence) = estimateTempo(onset: onset, rate: envRate)
        }
        let beat = 60 / bpm
        let firstBeat = phaseFrames / envRate

        // Per-beat energy (full band) for downbeat and drop decisions.
        let beatCount = max(0, Int((duration - firstBeat) / beat))
        var beatEnergy = [Double](repeating: 0, count: beatCount)
        for b in 0..<beatCount {
            let a = Int((firstBeat + Double(b) * beat) * envRate)
            let e = min(envFull.count, Int((firstBeat + Double(b + 1) * beat) * envRate))
            if e > a {
                var sum = 0.0
                for i in a..<e { sum += Double(envFull[i]) }
                beatEnergy[b] = sum / Double(e - a)
            }
        }
        // Downbeat: the beat offset whose bar starts carry the biggest energy jumps.
        var bestOffset = 0
        var bestScore = -1.0
        for q in 0..<4 {
            var s = 0.0
            var b = q + 4
            while b < beatCount {
                let jump = max(0, beatEnergy[b] - beatEnergy[b - 1])
                s += jump * jump
                b += 4
            }
            if s > bestScore {
                bestScore = s
                bestOffset = q
            }
        }
        let downbeat = firstBeat + Double(bestOffset) * beat
        let barDur = beat * 4
        let barCount = max(0, Int((duration - downbeat) / barDur))
        var bars = [Double](repeating: 0, count: barCount)
        for m in 0..<barCount {
            let first = bestOffset + m * 4
            let slice = beatEnergy[min(first, beatCount)..<min(first + 4, beatCount)]
            bars[m] = slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count)
        }

        // Drop window.
        var dropStart: Double
        var dropBars: Int
        var manual = track.manualBPM != nil
        if let s = track.manualDropStart, let e = track.manualDropEnd, e > s {
            manual = true
            dropStart = s
            dropBars = max(4, Int(((e - s) / barDur).rounded()))
        } else {
            (dropStart, dropBars) = chooseDrop(bars: bars, downbeat: downbeat, barDuration: barDur, duration: duration)
        }
        if dropStart + Double(dropBars) * barDur > duration {
            dropBars = max(1, Int((duration - dropStart) / barDur))
        }
        guard dropBars >= 1 else { throw AnalysisError.tooShort }
        let startBar = max(0, Int(((dropStart - downbeat) / barDur).rounded()))
        var dropEnergy = (0..<dropBars).map { i in startBar + i < bars.count ? bars[startBar + i] : 0 }
        if let lo = dropEnergy.min(), let hi = dropEnergy.max(), hi > lo {
            dropEnergy = dropEnergy.map { ($0 - lo) / (hi - lo) }
        } else {
            dropEnergy = dropEnergy.map { _ in 0.5 }
        }
        return TrackAnalysis(version: TrackAnalysis.currentVersion, bpm: bpm, firstDownbeat: downbeat, duration: duration,
                             dropStart: dropStart, dropEnd: dropStart + Double(dropBars) * barDur, dropBars: dropBars,
                             barEnergy: dropEnergy, tempoConfidence: confidence, manual: manual)
    }

    // MARK: - Envelopes

    private static func energyEnvelopes(url: URL) throws -> ([Float], [Float], Double, Double) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AnalysisError.unreadable(error.localizedDescription)
        }
        let format = file.processingFormat
        let sr = format.sampleRate
        let channels = Int(format.channelCount)
        let decim = max(1, Int((sr / targetRate).rounded()))
        let decRate = sr / Double(decim)
        let lowAlpha = Float(1 - exp(-2 * Double.pi * 150 / decRate))
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw AnalysisError.unreadable("buffer allocation failed")
        }

        var mono: [Float] = []
        var low: [Float] = []
        mono.reserveCapacity(Int(file.length) / decim + 1)
        low.reserveCapacity(Int(file.length) / decim + 1)
        var lp: Float = 0
        var acc: Float = 0
        var accCount = 0
        let gain = 1 / Float(channels * decim)
        while file.framePosition < file.length {
            do {
                try file.read(into: buffer, frameCount: chunk)
            } catch {
                throw AnalysisError.unreadable(error.localizedDescription)
            }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { throw AnalysisError.unreadable("not float PCM") }
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<channels { s += data[c][i] }
                acc += s
                accCount += 1
                if accCount == decim {
                    let v = acc * gain
                    mono.append(v)
                    lp += lowAlpha * (v - lp)
                    low.append(lp)
                    acc = 0
                    accCount = 0
                }
            }
        }
        let frames = mono.count / hop
        var full = [Float](repeating: 0, count: frames)
        var lowE = [Float](repeating: 0, count: frames)
        mono.withUnsafeBufferPointer { m in
            low.withUnsafeBufferPointer { l in
                guard let mb = m.baseAddress, let lb = l.baseAddress else { return }
                for f in 0..<frames {
                    var a: Float = 0
                    var b: Float = 0
                    vDSP_measqv(mb + f * hop, 1, &a, vDSP_Length(hop))
                    vDSP_measqv(lb + f * hop, 1, &b, vDSP_Length(hop))
                    full[f] = a
                    lowE[f] = b
                }
            }
        }
        return (full, lowE, decRate / Double(hop), Double(file.length) / sr)
    }

    /// Half-wave rectified log-energy flux, low band weighted (kicks), with local mean removed.
    static func onsetEnvelope(full: [Float], low: [Float]) -> [Double] {
        let n = full.count
        guard n > 2 else { return [] }
        var raw = [Double](repeating: 0, count: n)
        for i in 1..<n {
            let f = log(Double(full[i]) + 1e-9) - log(Double(full[i - 1]) + 1e-9)
            let l = log(Double(low[i]) + 1e-9) - log(Double(low[i - 1]) + 1e-9)
            raw[i] = 0.5 * max(0, f) + max(0, l)
        }
        // Subtract a 16-frame moving average to keep only the peaks.
        let w = 16
        var out = [Double](repeating: 0, count: n)
        var sum = 0.0
        for i in 0..<n {
            sum += raw[i]
            if i >= w { sum -= raw[i - w] }
            let mean = sum / Double(min(i + 1, w))
            out[i] = max(0, raw[i] - mean)
        }
        return out
    }

    // MARK: - Tempo

    static func estimateTempo(onset: [Double], rate: Double) -> (bpm: Double, phase: Double, confidence: Double) {
        let n = onset.count
        let minLag = Int((rate * 60 / Sim.maxFoldedBPM).rounded(.down))
        // Search down to half of the folded range so half-time grooves (e.g. 87 BPM) are found;
        // gameplay folds the tempo into 90–180 later (Sim.foldBPM).
        let maxLag = Int((rate * 60 / (Sim.minFoldedBPM / 2)).rounded(.up))
        guard n > maxLag * 4 else { return (Sim.referenceBPM, 0, 0) }
        var ac = [Double](repeating: 0, count: maxLag + 2)
        for lag in max(1, minLag - 1)...(maxLag + 1) {
            var s = 0.0
            for i in 0..<(n - lag) { s += onset[i] * onset[i + lag] }
            ac[lag] = s / Double(n - lag)
        }
        var bestLag = minLag
        var bestValue = -Double.infinity
        var total = 0.0
        for lag in minLag...maxLag {
            let bpm = rate * 60 / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 128) / 0.9, 2))
            let v = ac[lag] * prior
            total += v
            if v > bestValue {
                bestValue = v
                bestLag = lag
            }
        }
        // Parabolic interpolation around the peak.
        var lag = Double(bestLag)
        if bestLag > 1, bestLag < ac.count - 1 {
            let a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1]
            let d = a - 2 * b + c
            if abs(d) > 1e-12 { lag += 0.5 * (a - c) / d }
        }
        let coarse = rate * 60 / lag
        // Comb refinement ±3 BPM.
        var best = (bpm: coarse, phase: 0.0, score: -Double.infinity)
        var b = coarse - 3
        while b <= coarse + 3 {
            let (phase, score) = bestPhase(onset: onset, rate: rate, bpm: b)
            if score > best.score { best = (b, phase, score) }
            b += 0.05
        }
        // Snap to an integer BPM when it is (nearly) as good.
        let rounded = best.bpm.rounded()
        if abs(rounded - best.bpm) < 0.3 {
            let (phase, score) = bestPhase(onset: onset, rate: rate, bpm: rounded)
            if score >= best.score * 0.985 { best = (rounded, phase, score) }
        }
        let mean = total / Double(maxLag - minLag + 1)
        let confidence = mean > 0 ? bestValue / mean : 0
        return (best.bpm, best.phase, confidence)
    }

    /// Best beat phase (in envelope frames) for a BPM, and its mean comb score.
    static func bestPhase(onset: [Double], rate: Double, bpm: Double) -> (phase: Double, score: Double) {
        let period = rate * 60 / bpm
        let n = onset.count
        guard period > 1, n > Int(period) * 2 else { return (0, 0) }
        var bestPhase = 0.0
        var bestScore = -Double.infinity
        var phase = 0.0
        while phase < period {
            var s = 0.0
            var count = 0
            var t = phase
            while t < Double(n - 1) {
                let i = Int(t)
                let f = t - Double(i)
                s += onset[i] * (1 - f) + onset[i + 1] * f
                count += 1
                t += period
            }
            let score = count > 0 ? s / Double(count) : 0
            if score > bestScore {
                bestScore = score
                bestPhase = phase
            }
            phase += 0.5
        }
        return (bestPhase, bestScore)
    }

    // MARK: - Drop

    static func chooseDrop(bars: [Double], downbeat: Double, barDuration: Double, duration: Double) -> (start: Double, bars: Int) {
        // Length: multiple of 4 bars, closest to 30 s inside 20–45 s.
        var length = 0
        var bestDiff = Double.infinity
        var candidate = 4
        while Double(candidate) * barDuration <= maxDrop {
            let d = Double(candidate) * barDuration
            if d >= minDrop, abs(d - idealDrop) < bestDiff {
                bestDiff = abs(d - idealDrop)
                length = candidate
            }
            candidate += 4
        }
        if length == 0 {
            length = max(4, Int((idealDrop / barDuration).rounded()))
        }
        guard bars.count > length else {
            return (downbeat, min(bars.count, length))
        }
        var bestStart = 0
        var bestScore = -Double.infinity
        var s = 0
        while s + length <= bars.count {
            let window = bars[s..<(s + length)]
            let mean = window.reduce(0, +) / Double(length)
            let before = s >= 4 ? bars[(s - 4)..<s].reduce(0, +) / 4 : mean
            let score = mean + 0.6 * max(0, mean - before)
            if score > bestScore {
                bestScore = score
                bestStart = s
            }
            s += 4
        }
        return (downbeat + Double(bestStart) * barDuration, length)
    }
}

/// Disk cache for analyses (Caches/Analysis), keyed by file name + size + algorithm version.
enum AnalysisCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Analysis", isDirectory: true)
    }

    static func url(for track: Track) -> URL {
        let safe = track.id.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe)-\(track.fileSize)-v\(TrackAnalysis.currentVersion).json")
    }

    static func load(_ track: Track) -> TrackAnalysis? {
        guard let data = try? Data(contentsOf: url(for: track)),
              let a = try? JSONDecoder().decode(TrackAnalysis.self, from: data),
              a.version == TrackAnalysis.currentVersion else { return nil }
        return a
    }

    static func store(_ analysis: TrackAnalysis, for track: Track) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(analysis) {
            try? data.write(to: url(for: track), options: .atomic)
        }
    }
}
