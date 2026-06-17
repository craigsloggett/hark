import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var lastRecordingURL: URL?

    private var recorder: AVAudioRecorder?

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                print("Microphone access denied")
                return
            }
            beginRecording()
        }
    }

    func stop() {
        recorder?.stop()
        lastRecordingURL = recorder?.url
        recorder = nil
        isRecording = false
    }

    private func beginRecording() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: Self.makeOutputURL(), settings: settings)
            guard recorder.record() else {
                print("Recorder failed to start")
                return
            }
            self.recorder = recorder
            isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private static func makeOutputURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "hark-\(formatter.string(from: Date())).m4a"
        return directory.appendingPathComponent(name)
    }
}
