import UIKit
import SpriteKit
import SwiftUI

/// Hosts the SpriteKit scene full-bleed with SwiftUI HUD and overlays on top.
struct GameContainerView: View {
    let game: GameCoordinator
    @Environment(SaveManager.self) private var save

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    Color.black
                    if let scene = game.scene {
                        SpriteView(scene: scene,
                                   isPaused: game.phase == .paused || game.phase == .gameOver,
                                   preferredFramesPerSecond: 60,
                                   options: [.ignoresSiblingOrder],
                                   debugOptions: save.settings.showPerformanceOverlay
                                       ? [.showsFPS, .showsNodeCount, .showsDrawCount]
                                       : [])
                    }
                }
                .onAppear { game.prepareScene(viewSize: proxy.size) }
                .onChange(of: proxy.size) { _, newSize in game.prepareScene(viewSize: newSize) }
            }
            .ignoresSafeArea()

            HUDView(game: game)

            if save.settings.showPhysicsDebug {
                PhysicsDebugOverlay(game: game)
            }

            switch game.phase {
            case .loading:
                LoadingOverlay(message: game.loadingMessage).transition(.opacity)
            case .paused:
                PauseView(game: game).transition(.opacity)
            case .gameOver:
                if let result = game.result {
                    GameOverView(game: game, result: result).transition(.opacity)
                }
            case .tutorialComplete:
                TutorialCompleteView(game: game).transition(.opacity)
            case .playing, .dying:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: game.phase)
        .defersSystemGestures(on: .all)
        .onChange(of: save.settings) { _, newValue in game.applySettings(newValue) }
    }
}

private struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(NeonPalette.cyan.color)
                NeonLabel(text: message.uppercased(), color: NeonPalette.textPrimary.color, size: 12)
            }
            .padding(22)
            .holographicPanel()
        }
        .allowsHitTesting(true)
    }
}

private struct TutorialCompleteView: View {
    let game: GameCoordinator
    @Environment(AppCoordinator.self) private var app

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("TUTORIAL COMPLETE")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(NeonPalette.lime.color)
                    .shadow(color: NeonPalette.lime.opacity(0.6), radius: 10)
                NeonLabel(text: "STAGE 1 IS ALREADY CHALLENGING. GOOD LUCK.", size: 12)
                HStack(spacing: 12) {
                    Button("PLAY NOW") {
                        app.exitGame()
                        app.play(fromStage: 1)
                    }
                    .buttonStyle(NeonButtonStyle(prominent: true, minWidth: 160))
                    Button("MAIN MENU") { game.exitToMenu() }
                        .buttonStyle(NeonButtonStyle(tint: NeonPalette.textSecondary.color, minWidth: 160))
                }
            }
            .padding(24)
            .holographicPanel(tint: NeonPalette.lime.color)
        }
    }
}

/// Developer-only physics readout (Settings ▸ Developer). Bottom-left, inside the floor band.
private struct PhysicsDebugOverlay: View {
    let game: GameCoordinator

    var body: some View {
        let d = game.debug
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "x %.1f  y %.1f  vy %.0f", d.x, d.y, d.vy))
                    Text("grounded \(d.grounded ? "YES" : "no")  jumps \(d.jumps)  contacts \(d.supportCount)")
                    Text("support \(d.support)  mode \(d.mode)  grav \(d.gravity)\(d.mini ? "  mini" : "")")
                    Text("contact: \(d.lastContact)")
                    Text("event: \(d.lastEvent)")
                    Text(String(format: "seed %llu  tau %.2f  lag %.0f ms", d.seed, d.tau, d.lagMs))
                    Button("Copy flight log") { UIPasteboard.general.string = game.flightRecording }
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.green)
                .padding(6)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
        }
        .padding(.leading, 60)
        .padding(.bottom, 4)
    }
}
