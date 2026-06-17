import AVFoundation
import Foundation
@testable import hark
import Testing

@MainActor
struct AudioRecorderTests {
    @Test func startsIdle() {
        let recorder = AudioRecorder()
        #expect(recorder.isRecording == false)
        #expect(recorder.lastSessionURL == nil)
    }

    @Test func sessionNameFollowsTimestampPattern() {
        let date = Date(timeIntervalSince1970: 0)
        let name = AudioRecorder.sessionName(for: date)
        #expect(name.hasPrefix("hark-"))
        #expect(name.wholeMatch(of: /hark-\d{8}-\d{6}/) != nil)
    }

    @Test func systemAudioTapConstructsWithoutCapturing() {
        _ = SystemAudioTap()
    }

    @Test func outputCapacityDownsamplesWithLatencySlack() {
        // 48 kHz -> 16 kHz thirds the frame count; the slack guards the resampler's internal latency.
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
}
