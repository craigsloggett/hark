import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Failure modes when turning a recording session into a transcript.
enum TranscriptionError: LocalizedError {
    case localeNotSupported(Locale)
    case unreadableAudio(URL)
    case diarizationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .localeNotSupported(locale):
            "Transcription isn't available for \(locale.identifier)."
        case let .unreadableAudio(url):
            "Couldn't read \(url.lastPathComponent)."
        case let .diarizationFailed(reason):
            "Couldn't tell the speakers apart: \(reason)"
        }
    }
}

/// Transcribes a recording session's two tracks on-device with `SpeechAnalyzer`.
/// The microphone is the local user ("You"); the system-audio track is diarized into
/// individual remote speakers, and the two are merged into one chronological transcript.
struct TranscriptionService {
    private let diarizer = Diarizer()

    /// Transcribes `mic.wav` as "You", diarizes and transcribes `system.wav` into the
    /// remote speakers, and merges everything by start time.
    /// - Parameter offset: Seconds the system track started behind the mic, added to its
    ///   segments so both tracks share the mic's timeline before merging.
    func transcribeSession(
        at sessionURL: URL,
        offset: TimeInterval = 0,
        locale: Locale = .current
    ) async throws -> Transcript {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeNotSupported(locale)
        }
        try await ensureModel(for: supported)

        let micURL = sessionURL.appendingPathComponent("mic.wav")
        let systemURL = sessionURL.appendingPathComponent("system.wav")

        let you = try await transcribe(fileURL: micURL, locale: supported)
            .map { $0.segment(as: .you) }

        let remoteUtterances = try await transcribe(fileURL: systemURL, locale: supported)
        // Diarization only labels remote utterances; skip it when there are none.
        let turns = remoteUtterances.isEmpty ? [] : try await diarizer.turns(in: systemURL)
        let timeline = DiarizedTimeline(turns: turns)
        let them = remoteUtterances.map { utterance in
            // Fall back to one speaker when diarization found no turns to attribute to.
            let speaker = timeline.speaker(forUtteranceFrom: utterance.start, to: utterance.end) ?? .remote(1)
            return utterance.segment(as: speaker)
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

    /// One transcribed utterance before a speaker is attributed to it.
    private struct Utterance {
        let start: Double
        let end: Double
        let text: String

        func segment(as speaker: Speaker) -> TranscriptSegment {
            TranscriptSegment(start: start, end: end, speaker: speaker, text: text)
        }
    }

    private func transcribe(fileURL: URL, locale: Locale) async throws -> [Utterance] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.unreadableAudio(fileURL)
        }
        // The analyzer's results stream never finishes for an empty track.
        guard audioFile.length > 0 else { return [] }

        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Returns immediately; `finishAfterFile` ends the results stream once the file is consumed.
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var utterances: [Utterance] = []
        for try await result in transcriber.results {
            utterances.append(Utterance(
                start: result.range.start.seconds,
                end: result.range.end.seconds,
                text: String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return utterances
    }

    /// Installs the locale's speech model if needed, then reserves it: `SpeechAnalyzer`
    /// transcribes only reserved locales, not merely installed ones.
    private func ensureModel(for locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales.containsLocale(matching: locale)
        if !installed {
            let transcriber = Self.makeTranscriber(locale: locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
        try await reserve(locale)
    }

    /// Reserves `locale` with `AssetInventory` if it isn't already, freeing an existing
    /// reservation when the per-app limit is reached.
    private func reserve(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        guard !reserved.containsLocale(matching: locale) else { return }
        if try await AssetInventory.reserve(locale: locale) { return }
        if let existing = reserved.first {
            _ = await AssetInventory.release(reservedLocale: existing)
        }
        _ = try await AssetInventory.reserve(locale: locale)
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

private extension Sequence<Locale> {
    /// Whether any element matches `locale` by BCP-47 identifier, the comparison the Speech
    /// framework uses to key its installed and reserved locales.
    func containsLocale(matching locale: Locale) -> Bool {
        contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }
}
