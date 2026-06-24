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
            tuningRow(
                "Clustering threshold",
                value: $clusteringThreshold, range: 0.1 ... 1.0, step: 0.01,
                help: "Higher keeps more speaker embeddings apart as separate speakers."
            )
            tuningRow(
                "Speaker split (FA)",
                value: $diarizationFa, range: 0.0 ... 1.0, step: 0.01,
                help: "Higher splits embeddings into more speakers, lower merges them."
            )
            tuningRow(
                "Segmentation step ratio",
                value: $stepRatio, range: 0.0 ... 1.0, step: 0.01,
                help: "Lower sharpens turn boundaries at roughly 2x cost."
            )
            tuningRow(
                "Min segment duration",
                value: $minSegmentDuration, range: 0.0 ... 5.0, step: 0.1,
                help: "Shortest embedding segment, in seconds; lower lets brief turns get their own speaker."
            )
            tuningRow(
                "Utterance gap",
                value: $utteranceGap, range: 0.0 ... 2.0, step: 0.05,
                help: "Silence between tokens, in seconds, that ends an utterance."
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
