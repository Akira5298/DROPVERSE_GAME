import SwiftUI

/// Shared layout for secondary menu screens: backdrop, title bar with Back, content.
struct ScreenScaffold<Content: View>: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(SaveManager.self) private var save
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PianoRollBackdrop(animated: !(save.settings.reducedMotion || systemReduceMotion), dimmed: true)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Button {
                        app.navigate(to: .mainMenu)
                    } label: {
                        Label("BACK", systemImage: "chevron.left")
                    }
                    .buttonStyle(NeonButtonStyle(minWidth: 0))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(NeonPalette.textPrimary.color)
                        if let subtitle {
                            NeonLabel(text: subtitle)
                        }
                    }
                    Spacer()
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}
