import Foundation
import os

private let physicsLog = Logger(subsystem: "com.dropverse.game", category: "Physics")

/// One simulation step as recorded for diagnostics.
struct FlightSample {
    var tau: Double
    var x: Double
    var y: Double
    var vy: Double
    var grounded: Bool
    var jumps: Int
    var supportID: Int
    var mode: MovementMode
    var gravity: Double
    var events: StepEvents
    var held: Bool
    var pressed: Bool
}

/// Ring buffer of the last few seconds of player/physics state. Dumped to the log on death and
/// on unexpected loss of support, so "it just fell" reports come with evidence.
struct FlightRecorder {
    private var buffer: [FlightSample] = []
    private var head = 0
    let capacity: Int
    private(set) var lastDump = ""

    init(seconds: Double = 3, stepsPerSecond: Double = 120) {
        capacity = Int(seconds * stepsPerSecond)
        buffer.reserveCapacity(capacity)
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        head = 0
    }

    mutating func record(_ s: FlightSample) {
        if buffer.count < capacity {
            buffer.append(s)
        } else {
            buffer[head] = s
            head = (head + 1) % capacity
        }
    }

    var samples: [FlightSample] {
        buffer.count < capacity ? buffer : Array(buffer[head...] + buffer[..<head])
    }

    static func describeSupport(_ id: Int) -> String {
        if id == PlayerState.supportNone { return "none" }
        if id == PlayerState.supportCeiling { return "ceiling" }
        if id <= -1000 { return "floor#\(-1000 - id)" }
        return "object#\(id)"
    }

    /// Formats the recording (oldest first). Every 6th step is kept for readability, plus every
    /// step carrying an event.
    mutating func dump(reason: String, seed: UInt64) -> String {
        var lines = ["DROPVERSE flight recorder — \(reason) — stage seed \(seed)",
                     "tau      x        y       vy      grnd jumps support      mode grav in   events"]
        for (i, s) in samples.enumerated() where i % 6 == 0 || !s.events.isEmpty {
            var ev: [String] = []
            if s.events.contains(.jumped) { ev.append("jump") }
            if s.events.contains(.doubleJumped) { ev.append("DOUBLE") }
            if s.events.contains(.landed) { ev.append("land") }
            if s.events.contains(.ledgeCaught) { ev.append("ledge-catch") }
            if s.events.contains(.lostSupport) { ev.append("LOST-SUPPORT") }
            if s.events.contains(.pad) { ev.append("pad") }
            if s.events.contains(.orb) { ev.append("orb") }
            if s.events.contains(.portal) { ev.append("portal") }
            if s.events.contains(.died) { ev.append("DIED") }
            lines.append(String(format: "%7.3f %8.1f %7.1f %7.1f %@ %ld     %-12@ %@ %+.0f  %@%@ %@",
                                s.tau, s.x, s.y, s.vy, (s.grounded ? "yes " : "no  ") as NSString, s.jumps,
                                Self.describeSupport(s.supportID) as NSString, s.mode.rawValue as NSString, s.gravity,
                                (s.held ? "H" : "-") as NSString, (s.pressed ? "P" : "-") as NSString, ev.joined(separator: ",") as NSString))
        }
        let text = lines.joined(separator: "\n")
        lastDump = text
        // Log a local copy: the logger's message is an escaping autoclosure and must not capture
        // `self` inside a mutating method.
        physicsLog.notice("\(text, privacy: .public)")
        return text
    }

    static func logUnexpectedGroundLoss(_ s: FlightSample, previousSupport: Int) {
        physicsLog.warning("Lost support without jumping at tau=\(s.tau, format: .fixed(precision: 3)) x=\(s.x, format: .fixed(precision: 1)) y=\(s.y, format: .fixed(precision: 1)) previous=\(describeSupport(previousSupport), privacy: .public)")
    }
}

/// Values for the developer physics overlay.
struct PhysicsDebugSnapshot: Equatable {
    var x = 0.0
    var y = 0.0
    var vy = 0.0
    var grounded = false
    var jumps = 0
    var supportCount = 0
    var support = "none"
    var mode = "cube"
    var gravity = "normal"
    var mini = false
    var lastContact = ""
    var lastEvent = ""
    var seed: UInt64 = 0
    var tau = 0.0
    var lagMs = 0.0
}
