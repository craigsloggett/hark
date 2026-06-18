import AVFoundation
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var lastSessionURL: URL?

    private var micRecorder: AVAudioRecorder?
    private let systemTap = SystemAudioTap()
    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "AudioRecorder")

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
                logger.error("Microphone access denied")
                return
            }
            beginRecording()
        }
    }

    func stop() {
        micRecorder?.stop()
        systemTap.stop()
        micRecorder = nil
        isRecording = false
    }

    private func beginRecording() {
        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            logger.error("No documents directory available")
            return
        }
        let session = documents
            .appendingPathComponent(Self.sessionName(for: Date()), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)

            let micRecorder = try AVAudioRecorder(
                url: session.appendingPathComponent("mic.wav"),
                settings: Self.micSettings
            )
            guard micRecorder.record() else {
                logger.error("Microphone recorder failed to start")
                return
            }

            try systemTap.start(writingTo: session.appendingPathComponent("system.wav"))

            self.micRecorder = micRecorder
            lastSessionURL = session
            isRecording = true
        } catch {
            logger.error("Failed to start recording: \(error, privacy: .public)")
            micRecorder?.stop()
            systemTap.stop()
            micRecorder = nil
        }
    }

    static func sessionName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "hark-\(formatter.string(from: date))"
    }

    private static let micSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
}
