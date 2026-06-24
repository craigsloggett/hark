import SwiftUI

/// Advanced transcription tuning, persisted to `UserDefaults` via the same keys `Preferences` reads.
struct AdvancedSettingsView: View {
    @AppStorage(Preferences.Key.diarizationClusteringThreshold)
    private var clusteringThreshold = Preferences.Default.diarizationClusteringThreshold

    @AppStorage(Preferences.Key.diarizationSpeakerSensitivity)
    private var speakerSensitivity = Preferences.Default.diarizationSpeakerSensitivity

    @AppStorage(Preferences.Key.diarizationStepRatio)
    private var stepRatio = Preferences.Default.diarizationStepRatio

    @AppStorage(Preferences.Key.diarizationMinSegmentDuration)
    private var minSegmentDuration = Preferences.Default.diarizationMinSegmentDuration

    @AppStorage(Preferences.Key.utteranceGap)
    private var utteranceGap = Preferences.Default.utteranceGap

    var body: some View {
        Form {
            Section {
                Text(
                    "These settings fine-tune how Hark tells speakers apart. The defaults work "
                        + "well for most conversations, so adjust them only if you'd like to "
                        + "experiment. Reset to Defaults restores the original values at any time."
                )
                .foregroundStyle(.secondary)
            }

            tuningRow(
                "Telling voices apart",
                value: $clusteringThreshold, range: 0.1 ... 1.0, step: 0.01,
                help: "Higher makes Hark treat similar-sounding voices as separate people, "
                    + "so it tends to find more speakers."
            )
            tuningRow(
                "Number of speakers",
                value: $speakerSensitivity, range: 0.01 ... 0.5, step: 0.01,
                help: "Nudges the speaker count: higher tends to find more speakers, "
                    + "lower merges similar voices into fewer."
            )
            tuningRow(
                "Speaker change accuracy",
                value: $stepRatio, range: 0.01 ... 1.0, step: 0.01,
                help: "Lower pinpoints where one speaker stops and another starts more precisely, "
                    + "though transcribing takes a little longer."
            )
            tuningRow(
                "Shortest spoken turn",
                value: $minSegmentDuration, range: 0.0 ... 5.0, step: 0.1, unit: "s",
                help: "The shortest moment of speech Hark assigns to a speaker. Lower captures "
                    + "quick remarks; higher ignores them."
            )
            tuningRow(
                "Pause before a new line",
                value: $utteranceGap, range: 0.0 ... 2.0, step: 0.05, unit: "s",
                help: "How long a silence Hark waits through before starting a new line in the transcript."
            )

            Section {
                Button("Reset to Defaults") { resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tuningRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String = "",
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))) + unit)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resetToDefaults() {
        clusteringThreshold = Preferences.Default.diarizationClusteringThreshold
        speakerSensitivity = Preferences.Default.diarizationSpeakerSensitivity
        stepRatio = Preferences.Default.diarizationStepRatio
        minSegmentDuration = Preferences.Default.diarizationMinSegmentDuration
        utteranceGap = Preferences.Default.utteranceGap
    }
}
