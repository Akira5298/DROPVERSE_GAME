import Foundation
import Observation
import os

private let libraryLog = Logger(subsystem: "com.dropverse.game", category: "MusicLibrary")

/// Owns the track catalog and its (cached) analyses. Analysis runs in the background
/// once per file; results persist in Caches so later launches are instant.
@MainActor
@Observable
final class MusicLibrary {
    enum Status: Equatable {
        case pending
        case analyzing
        case ready
        case failed(String)
    }

    private(set) var tracks: [Track] = []
    private(set) var analyses: [String: TrackAnalysis] = [:]
    private(set) var status: [String: Status] = [:]
    private(set) var isAnalyzing = false

    @ObservationIgnored private var analysisTask: Task<Void, Never>?

    init() {
        reload()
    }

    func reload() {
        tracks = TrackCatalog.discover()
        for track in tracks {
            if let cached = AnalysisCache.load(track) {
                analyses[track.id] = cached
                status[track.id] = .ready
            } else {
                status[track.id] = .pending
            }
        }
        libraryLog.info("Discovered \(self.tracks.count) tracks, \(self.analyses.count) analysed")
    }

    /// Tracks that can be used for gameplay right now.
    var playableTracks: [Track] {
        tracks.filter { $0.isPlayable && analyses[$0.id] != nil }
    }

    var readyCount: Int { analyses.count }

    func analysis(for track: Track) -> TrackAnalysis? { analyses[track.id] }

    /// Analyses every pending track in the background (two at a time).
    func analyzeAllInBackground() {
        guard analysisTask == nil else { return }
        let pending = tracks.filter { status[$0.id] == .pending }
        guard !pending.isEmpty else { return }
        isAnalyzing = true
        analysisTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                var iterator = pending.makeIterator()
                for _ in 0..<2 {
                    guard let track = iterator.next() else { break }
                    group.addTask { await self?.analyze(track) }
                }
                while await group.next() != nil {
                    guard let track = iterator.next() else { continue }
                    group.addTask { await self?.analyze(track) }
                }
            }
            self?.isAnalyzing = false
            self?.analysisTask = nil
        }
    }

    /// Analyses one track now (used at run start if nothing is ready yet).
    func ensureAnalyzed(_ track: Track) async -> TrackAnalysis? {
        if let a = analyses[track.id] { return a }
        await analyze(track)
        return analyses[track.id]
    }

    private func analyze(_ track: Track) async {
        status[track.id] = .analyzing
        let result: Result<TrackAnalysis, Error> = await Task.detached(priority: .utility) { () -> Result<TrackAnalysis, Error> in
            do { return .success(try BeatAnalyzer.analyze(track: track)) } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let analysis):
            AnalysisCache.store(analysis, for: track)
            analyses[track.id] = analysis
            status[track.id] = .ready
        case .failure(let error):
            status[track.id] = .failed(error.localizedDescription)
            libraryLog.error("Analysis failed for \(track.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
