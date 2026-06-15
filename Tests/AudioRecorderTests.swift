@testable import hark
import Testing

/// Sanity check that the test target builds and Swift Testing is wired up.
/// Replace with behavioral tests as the recorder grows.
@MainActor
struct AudioRecorderTests {
    @Test func startsIdle() {
        let recorder = AudioRecorder()
        #expect(recorder.isRecording == false)
        #expect(recorder.lastRecordingURL == nil)
    }
}
