import Foundation

/// The player's jump envelope, measured by running the real simulation on flat ground
/// (mirrors `Tools/dropverse_sim.py::reachability`). Heights are above the take-off surface,
/// distances are horizontal travel at speed ×1. Reference values (big cube):
/// single tap ≈ 101 / 211, single held ≈ 156 / 269, double ≈ 325 high / 541 long.
struct Reachability: Equatable {
    var singleTapHeight: Double
    var singleTapDistance: Double
    var singleMaxHeight: Double
    var singleMaxDistance: Double
    var doubleMaxHeight: Double
    var doubleMaxDistance: Double

    static let big = Reachability.measure(mini: false)
    static let mini = Reachability.measure(mini: true)

    /// A gap wider than this cannot be crossed with one jump (hitbox overhang included).
    var singleGapLimit: Double { singleMaxDistance + Sim.halfBig * 2 }
    /// A gap wider than this cannot be crossed even with a double jump.
    var doubleGapLimit: Double { doubleMaxDistance + Sim.halfBig * 2 }

    static func measure(mini: Bool, dt: Double = 1.0 / 120.0) -> Reachability {
        func flight(secondAt: Double?, holdFirst: Bool = true, holdSecond: Bool = true) -> (height: Double, distance: Double) {
            let course = Course()
            var p = PlayerState(mini: mini)
            var t = 0.0
            var apex = 0.0
            var heldUntil = holdFirst ? Sim.holdMax + 0.02 : 0
            var secondDone = false
            var tookOff: Double?
            while t < 4 {
                var press = t == 0
                var held = t < heldUntil
                if let s = secondAt, !secondDone, let off = tookOff, t - off >= s {
                    press = true
                    secondDone = true
                    heldUntil = t + (holdSecond ? Sim.holdMax + 0.02 : 0)
                    held = holdSecond
                }
                let ev = WorldPhysics.step(course: course, player: &p, tauPrev: t, dtau: dt, held: held, pressed: press)
                t += dt
                if ev.contains(.jumped) { tookOff = t }
                apex = max(apex, p.y - p.half - Sim.floorY)
                if let off = tookOff, ev.contains(.landed) { return (apex, (t - off) * Sim.speed) }
            }
            return (apex, (t - (tookOff ?? 0)) * Sim.speed)
        }
        let tap = flight(secondAt: nil, holdFirst: false)
        let held = flight(secondAt: nil)
        var bestH = 0.0
        var bestD = 0.0
        for i in 1..<80 {
            let r = flight(secondAt: Double(i) * 0.01)
            bestH = max(bestH, r.height)
            bestD = max(bestD, r.distance)
        }
        return Reachability(singleTapHeight: tap.height, singleTapDistance: tap.distance,
                            singleMaxHeight: held.height, singleMaxDistance: held.distance,
                            doubleMaxHeight: bestH, doubleMaxDistance: bestD)
    }
}
