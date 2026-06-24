import AVFoundation
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AudioRecorder {
    enum TranscriptionState: Equatable {
        case idle
        case running
        case finished(URL)
        case failed(String)
    }

    /// The process-wide recorder. App Intents are instantiated by the system and need a shared
    /// reference to the same instance the menu bar UI observes.
    static let shared = AudioRecorder()

    private(set) var isRecording = false
    private(set) var lastSessionURL: URL?
    private(set) var transcriptionState = TranscriptionState.idle

    private var micRecorder: AVAudioRecorder?
    private var sessionStart: Date?
    private var lastSessionOffset: TimeInterval = 0
    private let systemTap = SystemAudioTap()
    private let transcriber = TranscriptionService()
    private let logger = Logger(category: "AudioRecorder")

    /// Starts recording when idle, or stops and transcribes the active recording.
    func toggleRecording() {
        if isRecording {
            stopAndTranscribe()
        } else {
            start()
        }
    }

    /// Stops the active recording and immediately transcribes it to disk.
    func stopAndTranscribe() {
        stop()
        transcribeLastSession()
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
        lastSessionOffset = systemTrackOffset()
        micRecorder = nil
        sessionStart = nil
        isRecording = false
    }

    /// How far the system track started behind the mic, in seconds. The mic always starts first,
    /// so the offset is non-negative.
    private func systemTrackOffset() -> TimeInterval {
        guard let sessionStart, let firstSystemAudio = systemTap.firstAudioTime() else { return 0 }
        return max(0, firstSystemAudio.timeIntervalSince(sessionStart))
    }

    func transcribeLastSession() {
        guard !isRecording, transcriptionState != .running, let session = lastSessionURL else { return }
        transcriptionState = .running
        Task {
            do {
                let transcript = try await transcriber.transcribeSession(at: session, offset: lastSessionOffset)
                transcriptionState = try .finished(transcriber.write(transcript, to: session))
            } catch {
                logger.error("Transcription failed: \(error, privacy: .public)")
                transcriptionState = .failed(error.localizedDescription)
            }
        }
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
            sessionStart = Date()

            try systemTap.start(writingTo: session.appendingPathComponent("system.wav"))

            self.micRecorder = micRecorder
            lastSessionURL = session
            transcriptionState = .idle
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
