import Foundation

/// Electronic genres DROPVERSE themes its worlds around.
enum Genre: String, Codable, CaseIterable, Sendable {
    case futureBass, dubstep, drumAndBass, house, trance, synthwave, other

    var displayName: String {
        switch self {
        case .futureBass: return "Future Bass"
        case .dubstep: return "Dubstep"
        case .drumAndBass: return "Drum & Bass"
        case .house: return "House"
        case .trance: return "Trance"
        case .synthwave: return "Synthwave"
        case .other: return "Electronic"
        }
    }

    /// Best-effort guess from a file name; tracks.json can override it.
    static func guess(fromFileName name: String) -> Genre {
        let n = name.lowercased()
        if n.contains("dnb") || n.contains("drum") || n.contains("jungle") { return .drumAndBass }
        if n.contains("dubstep") || n.contains("chillstep") || n.contains("formant") || n.contains("riddim") { return .dubstep }
        if n.contains("house") || n.contains("edm") || n.contains("techno") { return .house }
        if n.contains("trance") || n.contains("ambient") || n.contains("heaven") { return .trance }
        if n.contains("8bit") || n.contains("retro") || n.contains("80s") || n.contains("synth") { return .synthwave }
        if n.contains("future") { return .futureBass }
        return .other
    }
}

/// License metadata for one track (spec §24 license registry).
struct LicenseInfo: Codable, Hashable, Sendable {
    var name: String
    var url: String?
    var attribution: String?
    var commercialUse: Bool?
    var modificationAllowed: Bool?
}

/// One entry of Resources/Music/tracks.json. Every field except `file` is optional.
struct TrackEntry: Codable, Sendable {
    var file: String
    var title: String?
    var artist: String?
    var genre: Genre?
    /// Manual overrides for the analyzer (seconds / BPM).
    var bpm: Double?
    var dropStart: Double?
    var dropEnd: Double?
    var license: LicenseInfo?
    /// Set to true only once the license has been verified for commercial game use.
    var cleared: Bool?
}

struct TrackManifest: Codable, Sendable {
    var tracks: [TrackEntry]
}

/// A playable audio file found in the bundle.
struct Track: Identifiable, Hashable, Sendable {
    let id: String              // file name, unique within the Music folder
    let url: URL
    let title: String
    let artist: String
    let genre: Genre
    let license: LicenseInfo?
    let cleared: Bool
    let manualBPM: Double?
    let manualDropStart: Double?
    let manualDropEnd: Double?
    let fileSize: Int

    /// Debug builds may play tracks whose license is not yet marked as cleared, so you can
    /// develop with your library. Release builds only ship cleared tracks (spec §24).
    static var allowsUnclearedTracks: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var isPlayable: Bool { cleared || Self.allowsUnclearedTracks }
}

/// Finds audio in the bundle's `Music` folder and merges it with `tracks.json`.
enum TrackCatalog {
    static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aif", "aiff", "caf", "aac"]

    static func musicFolder(bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: "Music", withExtension: nil) { return url }
        let candidate = bundle.bundleURL.appendingPathComponent("Music", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static func loadManifest(in folder: URL) -> [String: TrackEntry] {
        let url = folder.appendingPathComponent("tracks.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(TrackManifest.self, from: data) else { return [:] }
        var map: [String: TrackEntry] = [:]
        for entry in manifest.tracks { map[entry.file.lowercased()] = entry }
        return map
    }

    static func discover(bundle: Bundle = .main) -> [Track] {
        guard let folder = musicFolder(bundle: bundle) else { return [] }
        let manifest = loadManifest(in: folder)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var tracks: [Track] = []
        for case let url as URL in enumerator {
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let fileName = url.lastPathComponent
            let entry = manifest[fileName.lowercased()]
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            tracks.append(Track(
                id: fileName,
                url: url,
                title: entry?.title ?? prettyTitle(fileName),
                artist: entry?.artist ?? "Unknown artist",
                genre: entry?.genre ?? Genre.guess(fromFileName: fileName),
                license: entry?.license,
                cleared: entry?.cleared ?? false,
                manualBPM: entry?.bpm,
                manualDropStart: entry?.dropStart,
                manualDropEnd: entry?.dropEnd,
                fileSize: size))
        }
        return tracks.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// "Port+In+A+Storm.mp3" -> "Port In A Storm"; "03 - Devour.mp3" -> "Devour".
    static func prettyTitle(_ fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "+", with: " ").replacingOccurrences(of: "_", with: " ")
        if let range = name.range(of: #"^\d{1,2}\s*-\s*"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}

/// Seeded shuffle bag (spec §5): no immediate repeats, prefers genre variety,
/// deterministic for a run seed.
struct TrackShuffleBag {
    private var rng: SeededGenerator
    private var bag: [Track] = []
    private let pool: [Track]
    private var history: [Track] = []

    init(tracks: [Track], seed: UInt64) {
        pool = tracks
        rng = SeededGenerator(seed: seed ^ 0x5EED_BA65)
    }

    mutating func next() -> Track? {
        guard !pool.isEmpty else { return nil }
        if bag.isEmpty { refill() }
        let last = history.last
        // Prefer a different genre than the last pick, and never the same track twice in a row.
        var index = bag.indices.first { bag[$0].genre != last?.genre && bag[$0].id != last?.id }
            ?? bag.indices.first { bag[$0].id != last?.id }
            ?? 0
        if bag.isEmpty { return nil }
        index = min(index, bag.count - 1)
        let track = bag.remove(at: index)
        history.append(track)
        return track
    }

    private mutating func refill() {
        bag = pool
        // Fisher–Yates with the deterministic generator.
        if bag.count > 1 {
            for i in stride(from: bag.count - 1, to: 0, by: -1) {
                let j = rng.nextInt(below: i + 1)
                bag.swapAt(i, j)
            }
        }
    }
}
