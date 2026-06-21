import Foundation

enum TranscriptionError: LocalizedError {
    case unreadableAudio(URL)
    case transcriptionFailed(String)
    case diarizationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableAudio(url):
            "Couldn't read \(url.lastPathComponent)."
        case let .transcriptionFailed(reason):
            "Couldn't transcribe the recording: \(reason)"
        case let .diarizationFailed(reason):
            "Couldn't tell the speakers apart: \(reason)"
        }
    }
}

/// Transcribes a recording session's two tracks on-device with FluidAudio's Parakeet model.
struct TranscriptionService {
    private let transcriber = Transcriber()
    private let diarizer = Diarizer()

    /// Transcribes `mic.wav` as "You", diarizes and transcribes `system.wav` into the remote
    /// speakers, and merges everything by start time.
    /// - Parameters:
    ///   - offset: Seconds the system track started behind the mic, added to its segments so
    ///     both tracks share the mic's timeline before merging.
    ///   - locale: Hints the multilingual model's script filtering.
    func transcribeSession(
        at sessionURL: URL,
        offset: TimeInterval = 0,
        locale: Locale = .current
    ) async throws -> Transcript {
        let micURL = sessionURL.appendingPathComponent("mic.wav")
        let systemURL = sessionURL.appendingPathComponent("system.wav")
        let gap = Self.utteranceGap

        let you = try await transcriber.tokens(in: micURL, locale: locale)
            .segments(resolving: { _ in .you }, gap: gap)

        let systemTokens = try await transcriber.tokens(in: systemURL, locale: locale)
        // Diarization only labels remote speech; skip it when the track is silent.
        let them: [TranscriptSegment]
        if systemTokens.isEmpty {
            them = []
        } else {
            let turns = try await diarizer.turns(in: systemURL)
            let timeline = DiarizedTimeline(turns: turns)
            // Fall back to one speaker when diarization found no turns to attribute to.
            them = systemTokens.segments(resolving: { timeline.speaker(at: $0) ?? .remote(1) }, gap: gap)
        }

        // `them` is built on the system file's own timeline; shifting realigns it onto the mic's.
        return Transcript.merging(you, them.shifted(by: offset))
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

    /// The silence between tokens, in seconds, that ends an utterance. Override with
    /// `HARK_UTTERANCE_GAP_MS` to tune segmentation on real meetings without rebuilding.
    private static var utteranceGap: Double {
        guard let raw = ProcessInfo.processInfo.environment["HARK_UTTERANCE_GAP_MS"],
              let milliseconds = Double(raw)
        else { return 0.6 }
        return milliseconds / 1000
    }
}
