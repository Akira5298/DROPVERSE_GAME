import SwiftUI
import UIKit

/// Platform-neutral color value usable from SwiftUI, UIKit and SpriteKit.
struct RGB: Equatable, Hashable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }
    func opacity(_ alpha: Double) -> Color { Color(red: r, green: g, blue: b, opacity: alpha) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    func uiColor(alpha: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: alpha) }
}

/// Shared DROPVERSE neon palette.
enum NeonPalette {
    static let background = RGB(hex: 0x070A14)
    static let panel = RGB(hex: 0x0E1426)
    static let panelEdge = RGB(hex: 0x2A3A66)

    static let cyan = RGB(hex: 0x19F0FF)
    static let magenta = RGB(hex: 0xFF2BD6)
    static let violet = RGB(hex: 0x8A5CFF)
    static let lime = RGB(hex: 0x39FF6A)
    static let orange = RGB(hex: 0xFF7A1A)
    static let hazard = RGB(hex: 0xFF3B6B)
    static let hazardDark = RGB(hex: 0x2A0716)

    static let textPrimary = RGB(hex: 0xEAF2FF)
    static let textSecondary = RGB(hex: 0x8C9BC2)

    // Piano-roll workspace
    static let laneWhite = RGB(hex: 0x111829)
    static let laneBlack = RGB(hex: 0x0B101D)
    static let laneLine = RGB(hex: 0x1A2340)
    static let beatLine = RGB(hex: 0x24325A)
    static let barLine = RGB(hex: 0x3C5290)
    static let keyWhite = RGB(hex: 0xB9C4DE)
    static let keyBlack = RGB(hex: 0x141A2A)
    static let ground = RGB(hex: 0x05070E)
}
