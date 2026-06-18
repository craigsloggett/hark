import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Failure modes when turning a recording session into a transcript.
enum TranscriptionError: LocalizedError {
    case localeNotSupported(Locale)
    case unreadableAudio(URL)

    var errorDescription: String? {
        switch self {
        case let .localeNotSupported(locale):
            "Transcription isn't available for \(locale.identifier)."
        case let .unreadableAudio(url):
            "Couldn't read \(url.lastPathComponent)."
        }
    }
}

/// Transcribes a recording session's two tracks on-device with `SpeechAnalyzer`
/// and merges them into a single chronological transcript.
struct TranscriptionService {
    /// Transcribes `mic.wav` (you) and `system.wav` (them) and merges by time.
    func transcribeSession(at sessionURL: URL, locale: Locale = .current) async throws -> Transcript {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeNotSupported(locale)
        }
        try await ensureModel(for: supported)

        let you = try await transcribe(
            fileURL: sessionURL.appendingPathComponent("mic.wav"),
            as: .you,
            locale: supported
        )
        let them = try await transcribe(
            fileURL: sessionURL.appendingPathComponent("system.wav"),
            as: .them,
            locale: supported
        )
        return Transcript.merging(you, them)
    }

    /// Writes `transcript.txt` and `transcript.json` into the session folder.
    /// - Returns: The URL of the written `transcript.txt`.
    func write(_ transcript: Transcript, to sessionURL: URL) throws -> URL {
        let textURL = sessionURL.appendingPathComponent("transcript.txt")
        try (transcript.plainText() + "\n").write(to: textURL, atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonURL = sessionURL.appendingPathComponent("transcript.json")
        try encoder.encode(transcript.segments).write(to: jsonURL, options: .atomic)

        return textURL
    }

    private func transcribe(fileURL: URL, as speaker: Speaker, locale: Locale) async throws -> [TranscriptSegment] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.unreadableAudio(fileURL)
        }

        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Returns immediately; `finishAfterFile` ends the results stream once the file is consumed.
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var segments: [TranscriptSegment] = []
        for try await result in transcriber.results {
            segments.append(TranscriptSegment(
                start: result.range.start.seconds,
                end: result.range.end.seconds,
                speaker: speaker,
                text: String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return segments
    }

    /// Downloads the locale's speech model if it isn't already installed. A nil
    /// installation request means the assets are already present.
    private func ensureModel(for locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
            .contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        guard !installed else { return }

        let transcriber = Self.makeTranscriber(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
    }
}
