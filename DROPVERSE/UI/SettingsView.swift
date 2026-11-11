import SwiftUI

struct SettingsView: View {
    @Environment(SaveManager.self) private var save
    @State private var confirmReset = false

    var body: some View {
        @Bindable var save = save
        ScreenScaffold(title: "SETTINGS") {
            Form {
                Section("Audio") {
                    LabeledSlider(title: "Music volume", value: $save.settings.musicVolume, range: 0...1, format: percent)
                    LabeledSlider(title: "Sound effects volume", value: $save.settings.sfxVolume, range: 0...1, format: percent)
                }

                Section {
                    Toggle("Show Beat Grid", isOn: $save.settings.showBeatGrid)
                    Toggle("Show Tap Timing Guides", isOn: $save.settings.showTapGuides)
                    Picker("Show Beat Subdivisions", selection: $save.settings.beatSubdivision) {
                        ForEach(BeatSubdivision.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    LabeledSlider(title: "Guide Opacity", value: $save.settings.guideOpacity, range: 0.2...1, format: percent)
                    Toggle("Timing feedback (PERFECT / GREAT / GOOD)", isOn: $save.settings.showTimingJudgments)
                        .disabled(!save.settings.showTapGuides)
                    LabeledSlider(title: "Audio/Visual Timing Offset", value: $save.settings.audioOffsetMilliseconds,
                                  range: -200...200, step: 5, format: { "\(Int($0)) ms" })
                    LabeledSlider(title: "Touch latency compensation", value: $save.settings.inputLatencyMilliseconds,
                                  range: 0...120, step: 5, format: { "\(Int($0)) ms" })
                } header: {
                    Text("Rhythm Assistance")
                } footer: {
                    Text("Guides only draw on top of the music; they never change jumps or collisions. Tap guides appear only for obstacles with a validated timing window. Raise the offset if guides look early compared with what you hear (e.g. Bluetooth headphones).")
                }

                Section("Visuals & accessibility") {
                    Picker("Particle intensity", selection: $save.settings.particleIntensity) {
                        ForEach(ParticleIntensity.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Toggle("Reduced flashing", isOn: $save.settings.reducedFlashing)
                    Toggle("Reduced motion", isOn: $save.settings.reducedMotion)
                    LabeledSlider(title: "Camera shake", value: $save.settings.cameraShake, range: 0...1, format: percent)
                    Toggle("Show performance overlay", isOn: $save.settings.showPerformanceOverlay)
                }

                #if DEBUG
                Section("Developer") {
                    Toggle("Physics debug overlay", isOn: $save.settings.showPhysicsDebug)
                    Toggle("Show collision bounds", isOn: $save.settings.showCollisionBounds)
                }
                #endif

                Section("Progress") {
                    Button("Reset progress", role: .destructive) { confirmReset = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NeonPalette.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .tint(NeonPalette.cyan.color)
        }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) { save.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unlocked stages, scores and statistics will be erased. Settings and your selected character are kept.")
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
        }
    }
}
