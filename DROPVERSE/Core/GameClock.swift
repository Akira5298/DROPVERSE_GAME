import Foundation
import QuartzCore

/// The single timing authority for gameplay.
///
/// Runs with music use `AudioClock` (AVAudioPlayerNode sample time). The tutorial and
/// the no-music fallback use `MonotonicGameClock` (host time).
protocol GameClock: AnyObject {
    /// Seconds since `start()`, excluding paused intervals.
    var currentTime: TimeInterval { get }
    var isRunning: Bool { get }
    func start()
    func pause()
    func resume()
    func reset()
}

final class MonotonicGameClock: GameClock {
    private let timeSource: () -> TimeInterval
    private var accumulated: TimeInterval = 0
    private var runningSince: TimeInterval?

    /// - Parameter timeSource: injectable for tests; defaults to the monotonic host clock.
    init(timeSource: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.timeSource = timeSource
    }

    var isRunning: Bool { runningSince != nil }

    var currentTime: TimeInterval {
        if let since = runningSince {
            return accumulated + (timeSource() - since)
        }
        return accumulated
    }

    func start() {
        accumulated = 0
        runningSince = timeSource()
    }

    func pause() {
        guard let since = runningSince else { return }
        accumulated += timeSource() - since
        runningSince = nil
    }

    func resume() {
        guard runningSince == nil else { return }
        runningSince = timeSource()
    }

    func reset() {
        accumulated = 0
        runningSince = nil
    }

    /// Jumps to `time` keeping the running/paused state (used by tutorial checkpoints).
    func seek(to time: TimeInterval) {
        accumulated = time
        if runningSince != nil { runningSince = timeSource() }
    }
}
