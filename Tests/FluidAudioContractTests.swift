import FluidAudio
import Testing

/// Pins the FluidAudio constants hark builds on: the recorder captures at `sampleRate`, `Transcriber`
/// pre-checks each track against the `minimumAudioDurationSeconds` floor, and `Preferences.Default`
/// defers to the community-1 diarization defaults. A FluidAudio version bump that changes any of
/// these trips a test so the assumptions get revisited.
struct FluidAudioContractTests {
    @Test func parakeetSampleRateIs16kHz() {
        #expect(ASRConstants.sampleRate == 16000)
    }

    @Test func parakeetMinimumDurationFloorIsUnchanged() {
        // 4800 = minimumAudioDurationSeconds (0.3) × sampleRate (16 kHz).
        #expect(ASRConstants.minimumRequiredSamples(forSampleRate: 16000) == 4800)
    }

    @Test func diarizationStepRatioDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.Segmentation.community.stepRatio == 0.2)
    }

    @Test func diarizationMinSegmentDefaultIsUnchanged() {
        #expect(OfflineDiarizerConfig.Embedding.community.minSegmentDurationSeconds == 1.0)
    }
}
