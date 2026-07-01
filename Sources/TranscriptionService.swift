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

/// A transcribed session plus each remote speaker's cross-session identity, keyed by on-disk token.
/// The transcript stays positional and portable (identities live in the `speakers.json` overlay).
struct Transcription {
    let transcript: Transcript
    let speakers: [String: SpeakerIdentity]
}

/// Transcribes a recording session's two tracks on-device with FluidAudio's Parakeet model.
struct TranscriptionService {
    private let transcriber = Transcriber()
    private let diarizer = Diarizer()
    private let speakerStore: SpeakerStore

    /// - Parameter speakerStore: defaults to the shared store so enrollment and the naming UI write
    ///   the same database; tests inject a temp-directory store.
    init(speakerStore: SpeakerStore = .shared) {
        self.speakerStore = speakerStore
    }

    /// Transcribes `mic.wav` as "You" and `system.wav` as the diarized remote speakers, resolves
    /// their cross-session identities, and merges both onto one timeline.
    /// - Parameters:
    ///   - offset: seconds the system track started behind the mic, added to its segments so
    ///     both tracks share the mic's timeline before merging.
    ///   - locale: hints the multilingual model's script filtering.
    func transcribeSession(
        at sessionURL: URL,
        offset: TimeInterval = 0,
        locale: Locale = .current
    ) async throws -> Transcription {
        let session = Session(url: sessionURL)
        let gap = Preferences.utteranceGap

        let you = try await transcriber.tokens(in: session.mic, locale: locale)
            .segments(resolving: { _ in .you }, gap: gap)

        let systemTokens = try await transcriber.tokens(in: session.system, locale: locale)
        // Diarization only labels remote speech (skip it when the track is silent).
        let them: [TranscriptSegment]
        var speakers: [String: SpeakerIdentity] = [:]
        if systemTokens.isEmpty {
            them = []
        } else {
            let diarization = try await diarizer.diarize(session.system)
            let timeline = DiarizedTimeline(turns: diarization.turns)
            // Fall back to one speaker when diarization found no turns to attribute to.
            them = systemTokens.segments(resolving: { timeline.speaker(at: $0) ?? .remote(1) }, gap: gap)
            speakers = await resolveIdentities(diarization, timeline: timeline)
        }

        // `them` is built on the system file's own timeline (shifting realigns it onto the mic's).
        let transcript = Transcript.merging(you, them.shifted(by: offset))
        return Transcription(transcript: transcript, speakers: speakers)
    }

    /// Writes `transcript.txt`, `transcript.json`, and `speakers.json` (when there are remote speakers).
    /// Named voices render into the text so a session recorded after naming shows names right away.
    /// - Returns: the URL of `transcript.txt`.
    func write(_ transcription: Transcription, to sessionURL: URL) throws -> URL {
        let session = Session(url: sessionURL)
        let transcript = transcription.transcript
        let text = transcript.plainText(names: transcription.speakers.names) + "\n"
        try text.write(to: session.transcriptText, atomically: true, encoding: .utf8)
        try transcript.segments.writeJSON(to: session.transcriptJSON)
        if !transcription.speakers.isEmpty {
            try transcription.speakers.writeJSON(to: session.speakers)
        }
        return session.transcriptText
    }

    /// Rewrites `transcript.txt` from the stored positional segments and the session's current
    /// `speakers.json` names, so naming a speaker updates that session's transcript in place without
    /// re-transcribing. The positional `transcript.json` is left untouched.
    static func rerenderTranscript(at sessionURL: URL) throws {
        let session = Session(url: sessionURL)
        let segments = try JSONDecoder().decode(
            [TranscriptSegment].self, from: Data(contentsOf: session.transcriptJSON)
        )
        let names = try session.loadSpeakers().names
        let text = Transcript(segments: segments).plainText(names: names) + "\n"
        try text.write(to: session.transcriptText, atomically: true, encoding: .utf8)
    }

    /// Resolves each diarized speaker's embedding to an identity, keyed by on-disk token to align
    /// with `transcript.json`.
    private func resolveIdentities(
        _ diarization: Diarization,
        timeline: DiarizedTimeline
    ) async -> [String: SpeakerIdentity] {
        var durations: [String: Float] = [:]
        for turn in diarization.turns {
            durations[turn.speakerID, default: 0] += Float(turn.end - turn.start)
        }
        let clusters = timeline.speakersByClusterID.compactMap { clusterID, _ -> SpeakerCluster? in
            guard let embedding = diarization.embeddings[clusterID] else { return nil }
            return SpeakerCluster(id: clusterID, embedding: embedding, duration: durations[clusterID] ?? 0)
        }
        guard !clusters.isEmpty else { return [:] }

        let byCluster = await speakerStore.resolve(clusters)
        var byToken: [String: SpeakerIdentity] = [:]
        for (clusterID, speaker) in timeline.speakersByClusterID {
            if let identity = byCluster[clusterID] {
                byToken[speaker.token] = identity
            }
        }
        return byToken
    }
}
