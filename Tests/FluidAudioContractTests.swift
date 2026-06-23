import FluidAudio
import Testing

/// Pins the FluidAudio Parakeet constants hark builds on: the recorder captures at `sampleRate`,
/// and `Transcriber` pre-checks each track against the `minimumAudioDurationSeconds` floor. A
/// FluidAudio version bump that changes either trips these so the assumptions get revisited.
struct FluidAudioContractTests {
    @Test func parakeetSampleRateIs16kHz() {
        #expect(ASRConstants.sampleRate == 16000)
    }

    @Test func parakeetMinimumDurationFloorIsUnchanged() {
        // 4800 = minimumAudioDurationSeconds (0.3) × sampleRate (16 kHz).
        #expect(ASRConstants.minimumRequiredSamples(forSampleRate: 16000) == 4800)
    }
}
