import Observation
import os
import SwiftUI

private let appLog = Logger(subsystem: "com.dropverse.game", category: "App")

/// Top-level navigation and ownership of long-lived services (save data, music engine,
/// music library with background analysis, pattern library).
@MainActor
@Observable
final class AppCoordinator {
    enum Route: Hashable {
        case mainMenu, stageSelect, characterSelect, musicLibrary, settings, credits, game
    }

    private(set) var route: Route = .mainMenu
    private(set) var game: GameCoordinator?
    let save: SaveManager
    let library: MusicLibrary
    let music: MusicManager
    private(set) var patterns: PatternLibrary
    private(set) var patternError: String?

    init() {
        save = SaveManager()
        library = MusicLibrary()
        music = MusicManager()
        do {
            patterns = try PatternLibrary.loadBundled()
        } catch {
            patterns = PatternLibrary(version: 0, patterns: [])
            patternError = String(describing: error)
            appLog.error("Pattern library failed to load: \(String(describing: error), privacy: .public)")
        }
        library.analyzeAllInBackground()
    }

    var canPlay: Bool { patternError == nil }

    func navigate(to route: Route) {
        guard route != .game else { return }
        self.route = route
    }

    /// Starts a run. Stages above the highest unlocked stage are clamped.
    func play(fromStage stage: Int = 1) {
        guard canPlay else { return }
        let startStage = max(1, min(stage, save.progress.highestUnlockedStage))
        startGame(stage: startStage, kind: .run)
    }

    func playTutorial() {
        guard canPlay else { return }
        startGame(stage: 1, kind: .tutorial)
    }

    private func startGame(stage: Int, kind: GameCoordinator.Kind) {
        game?.tearDown()
        game = GameCoordinator(save: save, music: music, library: library, patterns: patterns,
                               startStage: stage, kind: kind) { [weak self] in
            self?.exitGame()
        }
        route = .game
    }

    func exitGame() {
        game?.tearDown()
        route = .mainMenu
        game = nil
    }
}
