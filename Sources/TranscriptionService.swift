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
    ///   - offset: seconds the system track started behind the mic, added to its segments so
    ///     both tracks share the mic's timeline before merging.
    ///   - locale: hints the multilingual model's script filtering.
    func transcribeSession(
        at sessionURL: URL,
        offset: TimeInterval = 0,
        locale: Locale = .current
    ) async throws -> Transcript {
        let session = Session(url: sessionURL)
        let gap = Preferences.utteranceGap

        let you = try await transcriber.tokens(in: session.mic, locale: locale)
            .segments(resolving: { _ in .you }, gap: gap)

        let systemTokens = try await transcriber.tokens(in: session.system, locale: locale)
        // Diarization only labels remote speech; skip it when the track is silent.
        let them: [TranscriptSegment]
        if systemTokens.isEmpty {
            them = []
        } else {
            let turns = try await diarizer.turns(in: session.system)
            let timeline = DiarizedTimeline(turns: turns)
            // Fall back to one speaker when diarization found no turns to attribute to.
            them = systemTokens.segments(resolving: { timeline.speaker(at: $0) ?? .remote(1) }, gap: gap)
        }

        // `them` is built on the system file's own timeline; shifting realigns it onto the mic's.
        return Transcript.merging(you, them.shifted(by: offset))
    }

    /// Writes `transcript.txt` and `transcript.json` into the session folder.
    /// - Returns: the URL of the written `transcript.txt`.
    func write(_ transcript: Transcript, to sessionURL: URL) throws -> URL {
        let session = Session(url: sessionURL)
        try (transcript.plainText() + "\n").write(to: session.transcriptText, atomically: true, encoding: .utf8)
        try transcript.segments.writeJSON(to: session.transcriptJSON)
        return session.transcriptText
    }
}
