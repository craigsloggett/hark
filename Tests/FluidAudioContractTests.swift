import FluidAudio
@testable import hark
import Testing

/// Pins the FluidAudio constants and validation bounds hark builds on. The recorder captures at
/// `sampleRate`, `Transcriber` pre-checks each track against the `minimumAudioDurationSeconds`
/// floor, `Preferences.Default` tracks the community-1 diarization constants (deferring to some,
/// deliberately overriding others), and the Advanced settings sliders stay within
/// `OfflineDiarizerConfig.validate()`. A FluidAudio version bump that changes any of these trips a
/// test so the assumptions get revisited.
struct FluidAudioContractTests {
    @Test func parakeetSampleRateIs16kHz() {
        #expect(ASRConstants.sampleRate == 16000)
    }

    @Test func captureRateMatchesModelRate() {
        #expect(CaptureFormat.sampleRate == Double(ASRConstants.sampleRate))
    }

    @Test func parakeetMinimumDurationFloorIsUnchanged() {
        // 4800 = minimumAudioDurationSeconds (0.3) × sampleRate (16 kHz).
        #expect(ASRConstants.minimumRequiredSamples(forSampleRate: 16000) == 4800)
    }

    @Test func diarizationStepRatioDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.Segmentation.community.stepRatio == 0.2)
    }

    /// hark overrides this (`Preferences.Default.diarizationMinSegmentDuration` is 2.0) because the
    /// library's 1.0 over-segments compressed audio (pin the library value so a bump gets noticed).
    @Test func diarizationMinSegmentDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.Embedding.community.minSegmentDurationSeconds == 1.0)
    }

    @Test func speakerEmbeddingSizeIsUnchanged() {
        #expect(SpeakerManager.embeddingSize == 256)
    }

    /// The Fb (recall), gap-bridging, and overlap-trimming defaults defer to FluidAudio, so pin the
    /// community-1 constants and our mirrors together.
    @Test func diarizationSpeakerRecallDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.Clustering.community.warmStartFb == 0.8)
        #expect(OfflineDiarizerConfig.Clustering.community.warmStartFb == Preferences.Default.diarizationSpeakerRecall)
    }

    @Test func diarizationMinGapDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.PostProcessing.community.minGapDurationSeconds == 0.1)
        #expect(OfflineDiarizerConfig.PostProcessing.community.minGapDurationSeconds
            == Preferences.Default.diarizationMinGapDuration)
    }

    @Test func diarizationExclusiveSegmentsDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.PostProcessing.community.exclusiveSegments == true)
        #expect(OfflineDiarizerConfig.PostProcessing.community.exclusiveSegments
            == Preferences.Default.diarizationExclusiveSegments)
    }

    /// The ASR knobs defer to `ASRConfig`'s init defaults, also not exposed as constants.
    @Test func asrConfigDefaultsAreUnchanged() {
        #expect(ASRConfig().dualDecodeArbitration == false)
        #expect(ASRConfig().dualDecodeArbitration == Preferences.Default.asrDualDecodeArbitration)
        #expect(ASRConfig().parallelChunkConcurrency == 4)
        #expect(ASRConfig().parallelChunkConcurrency == Preferences.Default.asrParallelChunkConcurrency)
    }

    /// The match threshold default is an init default, not an exposed constant, so `Preferences`
    /// mirrors it. Pinning both means an SDK change to the default, or drift in our mirror, trips this.
    @Test func speakerMatchThresholdDefaultIsUnchanged() {
        #expect(SpeakerManager().speakerThreshold == 0.65)
        #expect(SpeakerManager().speakerThreshold == Float(Preferences.Default.speakerMatchThreshold))
    }

    /// The enrollment floor defers to FluidAudio's per-speaker minimum, also an init default.
    @Test func speakerMinSpeechDurationDefaultIsUnchanged() {
        #expect(SpeakerManager().minSpeechDuration == 1.0)
        #expect(SpeakerManager().minSpeechDuration == Float(Preferences.Default.speakerMinEnrollmentDuration))
    }

    /// `SpeakerStore.assign`'s contested-claim pick (`matches.first(where:)`) and the
    /// `HARK_SPEAKER_DEBUG` nearest both treat the first match as the closest, so pin FluidAudio's
    /// nearest-first ordering.
    @Test func findMatchingSpeakersReturnsNearestFirst() {
        var manager = SpeakerManager(speakerThreshold: 2)
        manager.upsertSpeaker(id: "near", currentEmbedding: embedding([1]), duration: 1)
        manager.upsertSpeaker(id: "far", currentEmbedding: embedding([0, 1]), duration: 1)

        let matches = manager.findMatchingSpeakers(with: embedding([1, 0.05]))
        #expect(matches.map(\.id) == ["near", "far"])
        #expect(matches.map(\.distance) == matches.map(\.distance).sorted())
    }

    /// A 256-d embedding with `leading` values at the front and zeros elsewhere.
    private func embedding(_ leading: [Float]) -> [Float] {
        var values = [Float](repeating: 0, count: SpeakerManager.embeddingSize)
        for (index, value) in leading.enumerated() {
            values[index] = value
        }
        return values
    }

    // MARK: Slider range bounds

    /// `OfflineDiarizerManager.process` validates on every run, so every reachable Advanced-slider
    /// position must produce a config that passes. Catches an SDK bound tightening under our ranges.
    @Test func advancedSliderExtremesPassValidation() throws {
        try OfflineDiarizerConfig(
            clusteringThreshold: 1.0, Fa: 0.01, Fb: 0.1, segmentationStepRatio: 0.01,
            minSegmentDuration: 0.0, minGapDuration: 0.0, exclusiveSegments: false
        ).validate()
        try OfflineDiarizerConfig(
            clusteringThreshold: 0.1, Fa: 0.5, Fb: 2.0, segmentationStepRatio: 1.0,
            minSegmentDuration: 5.0, minGapDuration: 1.0, exclusiveSegments: true
        ).validate()
    }

    /// The Fa and stepRatio sliders floor at 0.01, not 0, because validate() rejects non-positive values.
    @Test func nonPositiveFaAndStepRatioAreRejected() {
        #expect(throws: OfflineDiarizationError.self) {
            try OfflineDiarizerConfig(Fa: 0.0).validate()
        }
        #expect(throws: OfflineDiarizationError.self) {
            try OfflineDiarizerConfig(segmentationStepRatio: 0.0).validate()
        }
    }
}
