import Foundation

/// Per-genre world palette (spec §9). Safe surfaces always use cool/green tones and
/// hazards always use the hazard red/magenta family, regardless of theme, so the player
/// can tell them apart in every world.
struct WorldTheme: Equatable {
    let name: String
    let primary: RGB
    let secondary: RGB
    let accent: RGB
    let laneTint: RGB
    let glow: RGB

    static func forGenre(_ genre: Genre) -> WorldTheme {
        switch genre {
        case .futureBass:
            return WorldTheme(name: "Future Bass", primary: RGB(hex: 0x3DE8FF), secondary: RGB(hex: 0xFF6BD8),
                              accent: RGB(hex: 0xB79CFF), laneTint: RGB(hex: 0x2B6CFF), glow: RGB(hex: 0xFF9BE8))
        case .dubstep:
            return WorldTheme(name: "Dubstep", primary: RGB(hex: 0x9DFF2E), secondary: RGB(hex: 0x7A2BFF),
                              accent: RGB(hex: 0xFF2BD6), laneTint: RGB(hex: 0x3A1066), glow: RGB(hex: 0xB8FF3D))
        case .drumAndBass:
            return WorldTheme(name: "Drum & Bass", primary: RGB(hex: 0x19F0FF), secondary: RGB(hex: 0x1E6BFF),
                              accent: RGB(hex: 0xFF8A1A), laneTint: RGB(hex: 0x0D3A7A), glow: RGB(hex: 0x4FD8FF))
        case .house:
            return WorldTheme(name: "House", primary: RGB(hex: 0xFFA43D), secondary: RGB(hex: 0x3D7BFF),
                              accent: RGB(hex: 0xA65CFF), laneTint: RGB(hex: 0x4A2A10), glow: RGB(hex: 0xFFC46B))
        case .trance:
            return WorldTheme(name: "Trance", primary: RGB(hex: 0x5BF5FF), secondary: RGB(hex: 0x6A4DFF),
                              accent: RGB(hex: 0x2E5BFF), laneTint: RGB(hex: 0x14205A), glow: RGB(hex: 0x8FE9FF))
        case .synthwave:
            return WorldTheme(name: "Synthwave", primary: RGB(hex: 0xFF4FD8), secondary: RGB(hex: 0x29E7FF),
                              accent: RGB(hex: 0xFFD23D), laneTint: RGB(hex: 0x3A0F4F), glow: RGB(hex: 0xFF7AE6))
        case .other:
            return WorldTheme(name: "Electronic", primary: NeonPalette.cyan, secondary: NeonPalette.magenta,
                              accent: NeonPalette.violet, laneTint: RGB(hex: 0x1A2A55), glow: NeonPalette.cyan)
        }
    }

    /// Colour of safe, standable surfaces (constant across themes for readability).
    static let safe = RGB(hex: 0x2CFFC8)
    static let safeDark = RGB(hex: 0x07362E)
}
