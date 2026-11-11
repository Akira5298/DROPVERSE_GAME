import Foundation

/// SplitMix64 pseudo-random generator.
///
/// Level generation uses its own `nextDouble()` / `nextInt(below:)` instead of the
/// standard library's `random(in:using:)` because the stdlib's range-mapping
/// algorithm is not guaranteed to stay identical across Swift versions.
/// Stage seeds must reproduce the exact same course forever (retry, replays).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Uniform integer in [0, upperBound).
    mutating func nextInt(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        return Int(next() % UInt64(upperBound))
    }

    /// Derives a stable per-stage seed from a run seed.
    static func stageSeed(runSeed: UInt64, stage: Int) -> UInt64 {
        var generator = SeededGenerator(seed: runSeed ^ (UInt64(truncatingIfNeeded: stage) &* 0xD1B5_4A32_D192_ED03))
        return generator.next()
    }
}
