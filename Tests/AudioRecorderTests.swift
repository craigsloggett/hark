@testable import hark
import Testing

@MainActor
struct AudioRecorderTests {
    @Test func startsIdle() {
        let recorder = AudioRecorder()
        #expect(recorder.isRecording == false)
        #expect(recorder.lastRecordingURL == nil)
    }
}
