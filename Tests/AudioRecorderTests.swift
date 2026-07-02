import Foundation
@testable import hark
import Testing

@MainActor
struct AudioRecorderTests {
    /// Session folders already on disk use this name format, so it is a persisted-data contract:
    /// changing it orphans every existing recording in the browser.
    @Test func sessionNameFollowsTimestampPatternAndRoundTrips() {
        let date = Date(timeIntervalSince1970: 0)
        let name = AudioRecorder.sessionName(for: date)
        #expect(name.wholeMatch(of: /hark-\d{8}-\d{6}/) != nil)
        // The browser lists sessions by parsing the name back; a broken inverse hides recordings.
        #expect(AudioRecorder.date(from: name) == date)
        #expect(AudioRecorder.date(from: "not-a-session") == nil)
    }

    @Test func outputCapacityDownsamplesWithLatencySlack() {
        // 48 kHz -> 16 kHz thirds the frame count (the slack guards the resampler's internal latency).
        let capacity = SystemAudioTap.outputCapacity(
            inputFrames: 480,
            inputSampleRate: 48000,
            outputSampleRate: 16000
        )
        #expect(capacity == 176)
    }

    @Test func outputCapacityMatchesFramesAtEqualRates() {
        let capacity = SystemAudioTap.outputCapacity(
            inputFrames: 256,
            inputSampleRate: 16000,
            outputSampleRate: 16000
        )
        #expect(capacity == 272)
    }

    @Test func stopAndTranscribeOnIdleStaysIdle() {
        let recorder = AudioRecorder()
        recorder.stopAndTranscribe()
        #expect(recorder.isRecording == false)
        #expect(recorder.transcriptionState == .idle)
    }
}
