import AVFoundation
import Foundation
import os
import QuartzCore

private let audioLog = Logger(subsystem: "com.dropverse.game", category: "Audio")

/// A decoded drop segment ready for sample-accurate scheduling.
final class PreparedSegment: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let frames: AVAudioFramePosition
    let sampleRate: Double

    init(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        self.buffer = buffer
        self.frames = AVAudioFramePosition(buffer.frameLength)
        self.sampleRate = sampleRate
    }

    var duration: Double { Double(frames) / sampleRate }
}

/// Plays drop segments back-to-back on one AVAudioPlayerNode so the whole run lives on a
/// single, gapless sample timeline. That timeline is the game's timing authority (AudioClock).
@MainActor
final class MusicManager {
    nonisolated static let sampleRate: Double = 44_100
    nonisolated static let playerFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let sfxPlayer: AVAudioPlayerNode
    private var sfxCache: [SoundEffect: AVAudioPCMBuffer] = [:]
    let clock: AudioClock
    /// Called when the system interrupts audio or the engine configuration changes.
    var onInterruption: (@MainActor () -> Void)?
    private(set) var engineWasReset = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let sfxPlayer = AVAudioPlayerNode()
        self.engine = engine
        self.player = player
        self.sfxPlayer = sfxPlayer
        self.clock = AudioClock(player: player)
        engine.attach(player)
        engine.attach(sfxPlayer)
        engine.connect(player, to: engine.mainMixerNode, format: Self.playerFormat)
        engine.connect(sfxPlayer, to: engine.mainMixerNode, format: Self.playerFormat)
        configureSession()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.onInterruption?() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engineWasReset = true
                self?.onInterruption?()
            }
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    /// Activating the audio session can block for a noticeable time, so it runs off the main
    /// thread (Xcode's "AVAudioSession Hang Risk"). The first run starts seconds later, after the
    /// loading step, and `engine.start()` would activate the session itself if needed.
    private func configureSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
            } catch {
                audioLog.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// Starts a new timeline with `first` at sample 0.
    func startRun(with first: PreparedSegment?) {
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            audioLog.error("Engine failed to start: \(error.localizedDescription, privacy: .public)")
        }
        engineWasReset = false
        player.stop()
        clock.reset()
        if let first {
            player.scheduleBuffer(first.buffer, at: AVAudioTime(sampleTime: 0, atRate: Self.sampleRate), options: [], completionHandler: nil)
        }
        player.play()
    }

    /// Schedules a segment to begin exactly at `startSample` on the run timeline.
    func schedule(_ segment: PreparedSegment, atSample startSample: AVAudioFramePosition) {
        player.scheduleBuffer(segment.buffer, at: AVAudioTime(sampleTime: startSample, atRate: Self.sampleRate),
                              options: [], completionHandler: nil)
    }

    /// Plays a short effect on its own node (never touches the music timeline).
    func play(_ effect: SoundEffect, volume: Float) {
        guard volume > 0.01 else { return }
        if !engine.isRunning { try? engine.start() }
        let buffer: AVAudioPCMBuffer?
        if let cached = sfxCache[effect] {
            buffer = cached
        } else {
            buffer = SoundSynth.buffer(for: effect, format: Self.playerFormat)
            sfxCache[effect] = buffer
        }
        guard let buffer else { return }
        sfxPlayer.volume = volume
        sfxPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !sfxPlayer.isPlaying { sfxPlayer.play() }
    }

    func pause() {
        clock.freeze()
        player.pause()
        engine.pause()
    }

    func resume() {
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            audioLog.error("Engine failed to resume: \(error.localizedDescription, privacy: .public)")
        }
        player.play()
        clock.unfreeze()
    }

    func stop() {
        clock.freeze()
        player.stop()
    }

    // MARK: - Decoding

    /// Decodes [start, start + duration) of a file into the player format, with short
    /// fades to avoid clicks. Exactly `round(duration × 44.1 kHz)` frames long.
    nonisolated static func prepareSegment(url: URL, start: Double, duration: Double) throws -> PreparedSegment {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let startFrame = AVAudioFramePosition(max(0, start) * inFormat.sampleRate)
        let available = max(0, file.length - startFrame)
        let wantIn = AVAudioFrameCount(min(Double(available), duration * inFormat.sampleRate + 256))
        guard wantIn > 0, let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: wantIn) else {
            throw AnalysisError.unreadable("empty segment")
        }
        file.framePosition = startFrame
        try file.read(into: inBuffer, frameCount: wantIn)

        // Resample to 44.1 kHz keeping the source channel count, then map to stereo.
        let outFrames = AVAudioFrameCount((duration * sampleRate).rounded())
        guard let midFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: inFormat.channelCount),
              let converter = AVAudioConverter(from: inFormat, to: midFormat),
              let mid = AVAudioPCMBuffer(pcmFormat: midFormat, frameCapacity: outFrames + 4096) else {
            throw AnalysisError.unreadable("converter unavailable")
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: mid, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if status == .error {
            throw AnalysisError.unreadable(conversionError?.localizedDescription ?? "conversion failed")
        }

        guard let out = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: outFrames),
              let dst = out.floatChannelData, let src = mid.floatChannelData else {
            throw AnalysisError.unreadable("buffer allocation failed")
        }
        out.frameLength = outFrames
        let n = Int(outFrames)
        let have = min(n, Int(mid.frameLength))
        let srcChannels = Int(midFormat.channelCount)
        for c in 0..<2 {
            let s = src[min(c, srcChannels - 1)]
            let d = dst[c]
            for i in 0..<have { d[i] = s[i] }
            if have < n { for i in have..<n { d[i] = 0 } } // pad so the timeline stays exact
        }
        // Fades: 4 ms in, 30 ms out.
        let fadeIn = min(n, Int(0.004 * sampleRate))
        let fadeOut = min(n, Int(0.030 * sampleRate))
        for c in 0..<2 {
            let d = dst[c]
            if fadeIn > 0 { for i in 0..<fadeIn { d[i] *= Float(i) / Float(fadeIn) } }
            if fadeOut > 0 { for i in 0..<fadeOut { d[n - 1 - i] *= Float(i) / Float(fadeOut) } }
        }
        return PreparedSegment(buffer: out, sampleRate: sampleRate)
    }
}

/// Game clock derived from the player node's sample time (spec §18).
///
/// currentTime = playerSampleTime / rate + (now − renderHostTime) − output latency + user offset,
/// kept monotonic. When frozen (pause / death) it returns the last value.
final class AudioClock: GameClock {
    private let player: AVAudioPlayerNode
    private var last: TimeInterval = 0
    private var frozen = false
    /// User calibration (Settings ▸ Audio timing offset), seconds. Positive = visuals later.
    var userOffset: TimeInterval = 0

    init(player: AVAudioPlayerNode) {
        self.player = player
    }

    var isRunning: Bool { !frozen }

    var currentTime: TimeInterval {
        if frozen { return last }
        guard let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return last }
        var t = Double(playerTime.sampleTime) / playerTime.sampleRate
        if nodeTime.isHostTimeValid {
            let renderHost = AVAudioTime.seconds(forHostTime: nodeTime.hostTime)
            t += min(0.05, max(0, CACurrentMediaTime() - renderHost))
        }
        let session = AVAudioSession.sharedInstance()
        t -= session.outputLatency + session.ioBufferDuration
        t -= userOffset
        if t > last { last = t }
        return last
    }

    func reset() {
        last = 0
        frozen = false
    }

    func freeze() {
        _ = currentTime
        frozen = true
    }

    func unfreeze() {
        frozen = false
    }

    // GameClock conformance for owners that drive it generically.
    func start() { reset() }
    func pause() { freeze() }
    func resume() { unfreeze() }
}
