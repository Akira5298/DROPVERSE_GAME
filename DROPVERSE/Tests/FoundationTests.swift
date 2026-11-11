import CoreGraphics
import XCTest
@testable import Dropverse

final class SceneMetricsTests: XCTestCase {
    func testHeightIsConstantAcrossDevices() {
        for size in [CGSize(width: 667, height: 375), CGSize(width: 852, height: 393), CGSize(width: 932, height: 430)] {
            XCTAssertEqual(SceneMetrics(viewSize: size).sceneSize.height, SceneMetrics.designHeight)
        }
    }

    func testWidthFollowsAspectRatio() {
        let metrics = SceneMetrics(viewSize: CGSize(width: 1600, height: 900)) // 16:9
        XCTAssertEqual(metrics.sceneSize.width, 1280)
    }

    func testAspectIsClamped() {
        XCTAssertEqual(SceneMetrics(viewSize: CGSize(width: 3000, height: 500)).sceneSize.width,
                       (SceneMetrics.designHeight * SceneMetrics.maxAspect).rounded())
        XCTAssertEqual(SceneMetrics(viewSize: CGSize(width: 500, height: 500)).sceneSize.width,
                       (SceneMetrics.designHeight * SceneMetrics.minAspect).rounded())
    }

    func testZeroSizeFallsBackSafely() {
        XCTAssertEqual(SceneMetrics(viewSize: .zero).sceneSize.height, SceneMetrics.designHeight)
    }
}

final class GameClockTests: XCTestCase {
    func testPauseFreezesAndResumeContinues() {
        var now: TimeInterval = 100
        let clock = MonotonicGameClock(timeSource: { now })
        clock.start()
        now = 101.5
        XCTAssertEqual(clock.currentTime, 1.5, accuracy: 1e-9)
        clock.pause()
        now = 110
        XCTAssertEqual(clock.currentTime, 1.5, accuracy: 1e-9)
        clock.resume()
        now = 111
        XCTAssertEqual(clock.currentTime, 2.5, accuracy: 1e-9)
        clock.seek(to: 10)
        now = 112
        XCTAssertEqual(clock.currentTime, 11, accuracy: 1e-9)
        clock.reset()
        XCTAssertEqual(clock.currentTime, 0)
        XCTAssertFalse(clock.isRunning)
    }
}

final class ProgressionTests: XCTestCase {
    func testOldSaveFilesStillDecode() throws {
        // A Milestone 1 progress file has no tutorialCompleted key.
        let json = #"{"highestUnlockedStage":3,"highestStageReached":3,"bestScore":900,"totalStagesCleared":2,"totalRuns":4,"selectedSkin":"glitchPulse","stageBestScores":[],"stageClearCounts":[]}"#
        let p = try JSONDecoder().decode(PlayerProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.highestUnlockedStage, 3)
        XCTAssertEqual(p.selectedSkin, .glitchPulse)
        XCTAssertFalse(p.tutorialCompleted)
    }

    func testClearingStageUnlocksNext() {
        var progress = PlayerProgress()
        ProgressionManager.recordStageCleared(1, score: 1_300, progress: &progress)
        XCTAssertEqual(progress.highestUnlockedStage, 2)
        XCTAssertEqual(progress.stageClearCounts[1], 1)
        XCTAssertEqual(progress.stageBestScores[1], 1_300)
    }

    func testUnlockNeverRegresses() {
        var progress = PlayerProgress()
        progress.highestUnlockedStage = 10
        ProgressionManager.recordStageCleared(2, score: 10, progress: &progress)
        XCTAssertEqual(progress.highestUnlockedStage, 10)
    }

    func testBestScoreOnlyImproves() {
        var progress = PlayerProgress()
        XCTAssertTrue(ProgressionManager.recordRunEnded(stageReached: 3, finalScore: 500, progress: &progress))
        XCTAssertFalse(ProgressionManager.recordRunEnded(stageReached: 2, finalScore: 400, progress: &progress))
        XCTAssertEqual(progress.bestScore, 500)
        XCTAssertEqual(progress.highestStageReached, 3)
        XCTAssertEqual(progress.totalRuns, 2)
    }
}

@MainActor
final class SaveManagerTests: XCTestCase {
    func testSettingsAndProgressRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SaveManager(directory: directory)
        first.settings.reducedFlashing = true
        first.settings.particleIntensity = .low
        first.progress.selectedSkin = .prismDrive
        ProgressionManager.recordStageCleared(4, score: 999, progress: &first.progress)

        let second = SaveManager(directory: directory)
        XCTAssertTrue(second.settings.reducedFlashing)
        XCTAssertEqual(second.settings.particleIntensity, .low)
        XCTAssertEqual(second.progress.selectedSkin, .prismDrive)
        XCTAssertEqual(second.progress.highestUnlockedStage, 5)
        XCTAssertEqual(second.progress.stageBestScores[4], 999)
    }

    func testResetProgressKeepsSkin() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let save = SaveManager(directory: directory)
        save.progress.selectedSkin = .bassCrusher
        save.progress.highestUnlockedStage = 9
        save.resetProgress()
        XCTAssertEqual(save.progress.highestUnlockedStage, 1)
        XCTAssertEqual(save.progress.selectedSkin, .bassCrusher)
    }
}
