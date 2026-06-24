import SwiftUI

/// Advanced transcription tuning, persisted to `UserDefaults` via the same keys `Preferences` reads.
struct AdvancedSettingsView: View {
    @AppStorage(Preferences.Key.diarizationClusteringThreshold)
    private var clusteringThreshold = Preferences.Default.diarizationClusteringThreshold

    @AppStorage(Preferences.Key.diarizationFa)
    private var diarizationFa = Preferences.Default.diarizationFa

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
                help: "Higher makes Hark more willing to treat similar-sounding voices as separate people."
            )
            tuningRow(
                "Number of speakers",
                value: $diarizationFa, range: 0.0 ... 1.0, step: 0.01,
                help: "Higher leans toward finding more speakers; lower groups voices into fewer people."
            )
            tuningRow(
                "Speaker change accuracy",
                value: $stepRatio, range: 0.0 ... 1.0, step: 0.01,
                help: "Lower pinpoints where the speaker changes more precisely, "
                    + "though transcribing takes a little longer."
            )
            tuningRow(
                "Shortest spoken turn",
                value: $minSegmentDuration, range: 0.0 ... 5.0, step: 0.1,
                help: "The briefest moment of speech Hark credits to a speaker, in "
                    + "seconds. Lower captures quick remarks."
            )
            tuningRow(
                "Pause before a new line",
                value: $utteranceGap, range: 0.0 ... 2.0, step: 0.05,
                help: "How long a silence, in seconds, before Hark begins a new line in the transcript."
            )

            Section {
                Button("Reset to Defaults") { resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }

    private func tuningRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
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
        diarizationFa = Preferences.Default.diarizationFa
        stepRatio = Preferences.Default.diarizationStepRatio
        minSegmentDuration = Preferences.Default.diarizationMinSegmentDuration
        utteranceGap = Preferences.Default.utteranceGap
    }
}
