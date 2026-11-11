import SwiftUI

struct CreditsView: View {
    @Environment(MusicLibrary.self) private var library

    var body: some View {
        ScreenScaffold(title: "CREDITS") {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TitleWordmark(size: 34)
                    creditBlock("GAME", ["DROPVERSE — an original rhythm platformer."])
                    creditBlock("TECHNOLOGY", ["Swift · SwiftUI · SpriteKit · AVFoundation · Accelerate"])
                    creditBlock("ART", ["Characters, the DAW world, obstacles and effects are procedurally generated in code."])
                    creditBlock("MUSIC", musicCredits)
                    creditBlock("INSPIRATION", ["Inspired by the broad genre of rhythm platformers and by music-production software. Not affiliated with or endorsed by any game or DAW publisher."])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .holographicPanel()
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Attribution lines come from tracks.json (`license.attribution`), falling back to title/artist/license.
    private var musicCredits: [String] {
        let lines = library.tracks.filter(\.isPlayable).map { t -> String in
            if let attribution = t.license?.attribution { return attribution }
            let license = t.license?.name ?? "license not recorded"
            return "\"\(t.title)\" by \(t.artist) — \(license)"
        }
        return lines.isEmpty ? ["No tracks bundled."] : lines
    }

    private func creditBlock(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NeonLabel(text: title, color: NeonPalette.cyan.color)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(NeonPalette.textPrimary.color)
            }
        }
    }
}
