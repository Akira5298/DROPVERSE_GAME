import SwiftUI

struct CharacterSelectView: View {
    @Environment(SaveManager.self) private var save
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        ScreenScaffold(title: "CHARACTERS", subtitle: "COSMETIC ONLY · ALL SKINS SHARE IDENTICAL PHYSICS") {
            HStack(spacing: 14) {
                ForEach(CharacterSkin.all) { skin in
                    SkinCard(skin: skin,
                             selected: save.progress.selectedSkin == skin.id,
                             animated: !(save.settings.reducedMotion || systemReduceMotion)) {
                        save.progress.selectedSkin = skin.id
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct SkinCard: View {
    let skin: CharacterSkin
    let selected: Bool
    let animated: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                AnimatedCharacterPortrait(skin: skin, size: 108, animated: animated && selected)
                    .frame(height: 118)
                Text(skin.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(skin.primary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(skin.personality)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NeonPalette.textSecondary.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    ForEach([skin.primary, skin.secondary, skin.accent], id: \.self) { swatch in
                        Circle().fill(swatch.color).frame(width: 12, height: 12)
                    }
                }
                NeonLabel(text: selected ? "SELECTED" : "TAP TO SELECT",
                          color: selected ? skin.primary.color : NeonPalette.textSecondary.color, size: 10)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(NeonPalette.panel.opacity(0.9)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(skin.primary.color.opacity(selected ? 1 : 0.25), lineWidth: selected ? 2 : 1))
            .shadow(color: skin.primary.opacity(selected ? 0.5 : 0), radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(skin.name). \(skin.personality)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
