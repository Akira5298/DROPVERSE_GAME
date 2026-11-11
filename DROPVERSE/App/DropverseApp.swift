import SwiftUI

/// Application entry point.
///
/// Landscape-only orientation, full-screen and hidden status bar are configured
/// in the target's Info.plist build settings (see project.yml / README).
@main
struct DropverseApp: App {
    @State private var app = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .environment(app.save)
                .environment(app.library)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Never let gameplay keep running while the app is not frontmost.
            if newPhase != .active {
                app.game?.pause()
            }
        }
    }
}
