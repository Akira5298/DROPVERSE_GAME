import SwiftUI

/// Lists bundled tracks with their analysis (BPM, drop window), genre and license status.
struct MusicLibraryView: View {
    @Environment(MusicLibrary.self) private var library

    var body: some View {
        ScreenScaffold(title: "MUSIC LIBRARY",
                       subtitle: "\(library.tracks.count) TRACKS · \(library.readyCount) ANALYSED · \(library.playableTracks.count) PLAYABLE") {
            if library.tracks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(library.tracks) { track in
                            TrackRow(track: track, analysis: library.analysis(for: track),
                                     status: library.status[track.id] ?? .pending)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No tracks in the app bundle", systemImage: "waveform.slash")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(NeonPalette.magenta.color)
            Text("Copy audio files into DROPVERSE/Resources/Music and rebuild. Until then gameplay uses a silent 128 BPM clock.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(NeonPalette.textPrimary.color)
        }
        .padding(16)
        .holographicPanel(tint: NeonPalette.magenta.color)
    }
}

private struct TrackRow: View {
    let track: Track
    let analysis: TrackAnalysis?
    let status: MusicLibrary.Status

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(NeonPalette.textPrimary.color)
                    .lineLimit(1)
                NeonLabel(text: "\(track.artist.uppercased()) · \(track.genre.displayName.uppercased())", size: 10)
            }
            Spacer()
            if let a = analysis {
                NeonLabel(text: String(format: "%.0f BPM", a.bpm), color: NeonPalette.cyan.color, size: 11)
                NeonLabel(text: String(format: "DROP %d:%02d–%d:%02d", Int(a.dropStart) / 60, Int(a.dropStart) % 60,
                                       Int(a.dropEnd) / 60, Int(a.dropEnd) % 60), size: 10)
            } else {
                switch status {
                case .analyzing: ProgressView().scaleEffect(0.7)
                case .failed(let reason): NeonLabel(text: "FAILED", color: NeonPalette.hazard.color, size: 10).help(reason)
                default: NeonLabel(text: "QUEUED", size: 10)
                }
            }
            NeonLabel(text: track.cleared ? "CLEARED" : (Track.allowsUnclearedTracks ? "DEV ONLY" : "BLOCKED"),
                      color: track.cleared ? NeonPalette.lime.color : NeonPalette.orange.color, size: 10)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(NeonPalette.panel.opacity(0.85)))
    }
}
