import Foundation

/// Stable identifier persisted in `PlayerProgress`.
enum CharacterSkinID: String, Codable, CaseIterable, Identifiable, Sendable {
    case neonReactor
    case glitchPulse
    case bassCrusher
    case prismDrive

    var id: String { rawValue }
}

/// Cosmetic definition of a character. All skins share identical physics and collision size.
struct CharacterSkin: Identifiable, Equatable, Sendable {
    enum FaceStyle: Sendable {
        case reactor, glitch, crusher, prism
    }

    let id: CharacterSkinID
    let name: String
    let personality: String
    let primary: RGB
    let secondary: RGB
    let accent: RGB
    let body: RGB
    let faceStyle: FaceStyle

    static func skin(for id: CharacterSkinID) -> CharacterSkin {
        switch id {
        case .neonReactor:
            return CharacterSkin(
                id: id, name: "NEON REACTOR", personality: "Playful · Confident · Energetic",
                primary: RGB(hex: 0x19F0FF), secondary: RGB(hex: 0xFF2BD6), accent: RGB(hex: 0xE8FDFF),
                body: RGB(hex: 0x0B1630), faceStyle: .reactor)
        case .glitchPulse:
            return CharacterSkin(
                id: id, name: "GLITCH PULSE", personality: "Aggressive · Mischievous · Rebellious",
                primary: RGB(hex: 0x39FF6A), secondary: RGB(hex: 0x9B4DFF), accent: RGB(hex: 0xE6FFE9),
                body: RGB(hex: 0x07090C), faceStyle: .glitch)
        case .bassCrusher:
            return CharacterSkin(
                id: id, name: "BASS CRUSHER", personality: "Powerful · Tough · Aggressive",
                primary: RGB(hex: 0xFF7A1A), secondary: RGB(hex: 0x1EA0FF), accent: RGB(hex: 0xFFD9B0),
                body: RGB(hex: 0x1A1C22), faceStyle: .crusher)
        case .prismDrive:
            return CharacterSkin(
                id: id, name: "PRISM DRIVE", personality: "Cool · Playful · Precise",
                primary: RGB(hex: 0x3DF2FF), secondary: RGB(hex: 0xA66BFF), accent: RGB(hex: 0xFF6BD8),
                body: RGB(hex: 0x10142A), faceStyle: .prism)
        }
    }

    static let all: [CharacterSkin] = CharacterSkinID.allCases.map { CharacterSkin.skin(for: $0) }
}
