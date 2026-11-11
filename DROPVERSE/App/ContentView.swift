import SwiftUI

/// Root view: switches between screens based on `AppCoordinator.route`.
struct ContentView: View {
    @Environment(AppCoordinator.self) private var app

    var body: some View {
        ZStack {
            NeonPalette.background.color.ignoresSafeArea()

            switch app.route {
            case .mainMenu:
                MainMenuView().transition(.opacity)
            case .stageSelect:
                StageSelectView().transition(.opacity)
            case .characterSelect:
                CharacterSelectView().transition(.opacity)
            case .musicLibrary:
                MusicLibraryView().transition(.opacity)
            case .settings:
                SettingsView().transition(.opacity)
            case .credits:
                CreditsView().transition(.opacity)
            case .game:
                if let game = app.game {
                    GameContainerView(game: game).transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.route)
    }
}
