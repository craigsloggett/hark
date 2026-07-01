import SwiftUI

/// Advanced transcription tuning, persisted to `UserDefaults` via the same keys `Preferences` reads.
struct AdvancedSettingsView: View {
    @AppStorage(Preferences.Key.speakerMatchThreshold)
    private var speakerMatchThreshold = Preferences.Default.speakerMatchThreshold

    @AppStorage(Preferences.Key.speakerMinEnrollmentDuration)
    private var speakerMinEnrollmentDuration = Preferences.Default.speakerMinEnrollmentDuration

    @AppStorage(Preferences.Key.voiceprintMaxSamples)
    private var voiceprintMaxSamples = Preferences.Default.voiceprintMaxSamples

    @AppStorage(Preferences.Key.diarizationClusteringThreshold)
    private var clusteringThreshold = Preferences.Default.diarizationClusteringThreshold

    @AppStorage(Preferences.Key.diarizationSpeakerSensitivity)
    private var speakerSensitivity = Preferences.Default.diarizationSpeakerSensitivity

    @AppStorage(Preferences.Key.diarizationSpeakerRecall)
    private var speakerRecall = Preferences.Default.diarizationSpeakerRecall

    @AppStorage(Preferences.Key.diarizationStepRatio)
    private var stepRatio = Preferences.Default.diarizationStepRatio

    @AppStorage(Preferences.Key.diarizationMinSegmentDuration)
    private var minSegmentDuration = Preferences.Default.diarizationMinSegmentDuration

    @AppStorage(Preferences.Key.diarizationMinGapDuration)
    private var minGapDuration = Preferences.Default.diarizationMinGapDuration

    @AppStorage(Preferences.Key.diarizationExclusiveSegments)
    private var exclusiveSegments = Preferences.Default.diarizationExclusiveSegments

    @AppStorage(Preferences.Key.diarizationMaxSpeakers)
    private var maxSpeakers = Preferences.Default.diarizationMaxSpeakers

    @AppStorage(Preferences.Key.utteranceGap)
    private var utteranceGap = Preferences.Default.utteranceGap

    @AppStorage(Preferences.Key.asrDualDecodeArbitration)
    private var dualDecodeArbitration = Preferences.Default.asrDualDecodeArbitration

    @AppStorage(Preferences.Key.asrParallelChunkConcurrency)
    private var parallelChunkConcurrency = Preferences.Default.asrParallelChunkConcurrency

    var body: some View {
        Form {
            Section {
                Text(
                    "These settings fine-tune how Hark transcribes speech and tells speakers apart. "
                        + "The defaults work well for most conversations, so adjust them only if you'd "
                        + "like to experiment. Reset to Defaults restores the original values at any time."
                )
                .foregroundStyle(.secondary)
            }

            Section("Saved voices") {
                tuningRow(
                    "Matching a known voice",
                    value: $speakerMatchThreshold, range: 0.1 ... 1.5, step: 0.05,
                    help: "Lower is stricter about matching this session's speakers to voices Hark has "
                        + "saved before, so it reuses a saved voice less readily."
                )
                tuningRow(
                    "Speech needed to remember a voice",
                    value: $speakerMinEnrollmentDuration, range: 0.0 ... 10.0, step: 0.5, unit: "s",
                    help: "How long someone must speak before Hark saves their voice to recognise next time."
                )
                stepperRow(
                    "Samples kept per voice",
                    value: $voiceprintMaxSamples, range: 1 ... 20,
                    help: "How many recent clips Hark averages into each saved voice. More captures "
                        + "natural variation at a little more storage."
                )
            }

            Section("Telling speakers apart") {
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
                    "Keeping a voice together",
                    value: $speakerRecall, range: 0.1 ... 2.0, step: 0.05,
                    help: "Higher keeps borderline moments with the same speaker instead of "
                        + "splitting them onto another."
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
                    "Bridging short pauses",
                    value: $minGapDuration, range: 0.0 ... 1.0, step: 0.05, unit: "s",
                    help: "Silences shorter than this stay within one speaker's turn instead of "
                        + "breaking it into two."
                )
                toggleRow(
                    "One speaker at a time",
                    value: $exclusiveSegments,
                    help: "When two voices overlap, attribute each moment to a single speaker."
                )
                stepperRow(
                    "Limit number of speakers",
                    value: $maxSpeakers, range: 0 ... 10,
                    valueText: { $0 == 0 ? "Auto" : "\($0)" },
                    help: "Cap how many speakers Hark may find in a session; it tends to find close "
                        + "to this many. Auto lets it decide."
                )
            }

            Section("Transcription") {
                tuningRow(
                    "Pause before a new line",
                    value: $utteranceGap, range: 0.0 ... 2.0, step: 0.05, unit: "s",
                    help: "How long a silence Hark waits through before starting a new line in the transcript."
                )
            }

            Section {
                toggleRow(
                    "Higher-accuracy transcription",
                    value: $dualDecodeArbitration,
                    help: "Tries several decoding strategies for better wording, at a little more time."
                )
                stepperRow(
                    "Transcription parallelism",
                    value: $parallelChunkConcurrency, range: 1 ... 8,
                    help: "How many audio chunks Hark transcribes at once. Higher is faster but uses "
                        + "more CPU and memory."
                )
                if restartPending {
                    Label(
                        "Restart Hark for your changes to take effect.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Transcription engine")
            } footer: {
                Text("These settings take effect after you restart Hark.")
            }

            Section {
                Button("Reset to Defaults") { resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(height: 540)
    }

    // MARK: Rows

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

    private func toggleRow(
        _ title: String,
        value: Binding<Bool>,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: value)
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stepperRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        valueText: (Int) -> String = { "\($0)" },
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: value, in: range) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(valueText(value.wrappedValue))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Logic

    /// True when a restart-scoped setting differs from the value the running engine loaded at launch.
    private var restartPending: Bool {
        dualDecodeArbitration != Preferences.Launch.asrDualDecodeArbitration
            || parallelChunkConcurrency != Preferences.Launch.asrParallelChunkConcurrency
    }

    private func resetToDefaults() {
        speakerMatchThreshold = Preferences.Default.speakerMatchThreshold
        speakerMinEnrollmentDuration = Preferences.Default.speakerMinEnrollmentDuration
        voiceprintMaxSamples = Preferences.Default.voiceprintMaxSamples
        clusteringThreshold = Preferences.Default.diarizationClusteringThreshold
        speakerSensitivity = Preferences.Default.diarizationSpeakerSensitivity
        speakerRecall = Preferences.Default.diarizationSpeakerRecall
        stepRatio = Preferences.Default.diarizationStepRatio
        minSegmentDuration = Preferences.Default.diarizationMinSegmentDuration
        minGapDuration = Preferences.Default.diarizationMinGapDuration
        exclusiveSegments = Preferences.Default.diarizationExclusiveSegments
        maxSpeakers = Preferences.Default.diarizationMaxSpeakers
        utteranceGap = Preferences.Default.utteranceGap
        dualDecodeArbitration = Preferences.Default.asrDualDecodeArbitration
        parallelChunkConcurrency = Preferences.Default.asrParallelChunkConcurrency
    }
}
