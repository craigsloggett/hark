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
}
