import Foundation
import Observation
import os

private let saveLog = Logger(subsystem: "com.dropverse.game", category: "Save")

/// Stores settings and progress as JSON in Application Support. Writes happen on change.
///
/// JSON was chosen over SwiftData for these two small documents: they are single
/// records, need no queries, and stay human-readable for debugging. SwiftData can be
/// introduced later for run history without changing this API.
@MainActor
@Observable
final class SaveManager {
    var settings: GameSettings {
        didSet {
            guard settings != oldValue else { return }
            write(settings, to: Self.settingsFileName)
        }
    }

    var progress: PlayerProgress {
        didSet {
            guard progress != oldValue else { return }
            write(progress, to: Self.progressFileName)
        }
    }

    private let directory: URL

    private static let settingsFileName = "settings.json"
    private static let progressFileName = "progress.json"

    /// - Parameter directory: override for tests; defaults to Application Support/Dropverse.
    init(directory: URL? = nil) {
        let resolved = directory ?? Self.defaultDirectory()
        do {
            try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        } catch {
            saveLog.error("Could not create save directory: \(error.localizedDescription, privacy: .public)")
        }
        self.directory = resolved
        self.settings = Self.read(GameSettings.self, from: resolved.appendingPathComponent(Self.settingsFileName)) ?? GameSettings()
        self.progress = Self.read(PlayerProgress.self, from: resolved.appendingPathComponent(Self.progressFileName)) ?? PlayerProgress()
    }

    /// Resets progression but keeps the selected character and all settings.
    func resetProgress() {
        var fresh = PlayerProgress()
        fresh.selectedSkin = progress.selectedSkin
        progress = fresh
    }

    // MARK: - File IO

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Dropverse", isDirectory: true)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            saveLog.error("Discarding unreadable save file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to fileName: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            saveLog.error("Failed to write \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
