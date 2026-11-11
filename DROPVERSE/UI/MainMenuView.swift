import SwiftUI

struct MainMenuView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(SaveManager.self) private var save
    @Environment(MusicLibrary.self) private var library
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var animate: Bool { !(save.settings.reducedMotion || systemReduceMotion) }

    var body: some View {
        ZStack {
            PianoRollBackdrop(animated: animate)
                .ignoresSafeArea()

            LinearGradient(colors: [NeonPalette.background.opacity(0.92), NeonPalette.background.opacity(0.35), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 24) {
                titleBlock
                Spacer(minLength: 12)
                menuButtons
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }

    private var titleBlock: some View {
        let skin = CharacterSkin.skin(for: save.progress.selectedSkin)
        return VStack(alignment: .leading, spacing: 12) {
            TitleWordmark(size: 54)
            NeonLabel(text: "EVERY DROP IS A NEW WORLD.", color: NeonPalette.magenta.color, size: 13)

            HStack(spacing: 14) {
                AnimatedCharacterPortrait(skin: skin, size: 84, animated: animate)
                VStack(alignment: .leading, spacing: 4) {
                    Text(skin.name)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(skin.primary.color)
                    NeonLabel(text: "BEST  \(save.progress.bestScore.formatted())")
                    NeonLabel(text: "UNLOCKED  STAGE \(save.progress.highestUnlockedStage)")
                    NeonLabel(text: "TRACKS  \(library.playableTracks.count) READY / \(library.tracks.count)")
                }
            }
            .padding(.top, 6)
            if let error = app.patternError {
                NeonLabel(text: "LEVEL DATA ERROR: \(error)", color: NeonPalette.hazard.color, size: 10)
                    .lineLimit(2)
            }
        }
    }

    private var menuButtons: some View {
        VStack(spacing: 7) {
            Button("PLAY") { app.play(fromStage: 1) }
                .buttonStyle(NeonButtonStyle(tint: NeonPalette.cyan.color, prominent: true))
                .disabled(!app.canPlay)
            Button(save.progress.tutorialCompleted ? "TUTORIAL" : "TUTORIAL (RECOMMENDED)") { app.playTutorial() }
                .buttonStyle(NeonButtonStyle(tint: NeonPalette.lime.color))
                .disabled(!app.canPlay)
            Button("STAGE SELECT") { app.navigate(to: .stageSelect) }
                .buttonStyle(NeonButtonStyle())
            Button("CHARACTERS") { app.navigate(to: .characterSelect) }
                .buttonStyle(NeonButtonStyle(tint: NeonPalette.magenta.color))
            Button("MUSIC LIBRARY") { app.navigate(to: .musicLibrary) }
                .buttonStyle(NeonButtonStyle(tint: NeonPalette.violet.color))
            Button("SETTINGS") { app.navigate(to: .settings) }
                .buttonStyle(NeonButtonStyle(tint: NeonPalette.textSecondary.color))
            Button("CREDITS") { app.navigate(to: .credits) }
                .buttonStyle(NeonButtonStyle(tint: NeonPalette.textSecondary.color))
        }
        .padding(12)
        .holographicPanel()
    }
}
