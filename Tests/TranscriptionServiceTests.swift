import Foundation
@testable import hark
import Testing

/// Exercises the file-only parts of `TranscriptionService` (re-rendering a stored transcript) and
/// the `speakers.json` overlay reader, which need no audio or models.
struct TranscriptionServiceTests {
    private func temporarySession() throws -> Session {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hark-transcription-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Session(url: url)
    }

    @Test func rerenderUsesTranscriptOverride() throws {
        let session = try temporarySession()
        defer { try? FileManager.default.removeItem(at: session.url) }

        try [
            TranscriptSegment(start: 0, end: 1, speaker: .you, text: "Morning"),
            TranscriptSegment(start: 2, end: 3, speaker: .remote(1), text: "Hi"),
        ].writeJSON(to: session.transcriptJSON)
        // A transcript-only override needs no voiceprint to render.
        try session.writeSpeakers(["speaker1": SessionSpeaker(nameOverride: "Alice")])

        try TranscriptionService.rerenderTranscript(at: session.url, voiceprints: [])

        let text = try String(contentsOf: session.transcriptText, encoding: .utf8)
        #expect(text.contains("[00:00:00] You: Morning"))
        #expect(text.contains("[00:00:02] Alice: Hi"))
    }

    @Test func rerenderResolvesBoundVoiceprintName() throws {
        let session = try temporarySession()
        defer { try? FileManager.default.removeItem(at: session.url) }

        try [TranscriptSegment(start: 0, end: 1, speaker: .remote(1), text: "Hi")]
            .writeJSON(to: session.transcriptJSON)
        try session.writeSpeakers(["speaker1": SessionSpeaker(voiceprintID: "v1")])
        let sample = VoiceSample(id: UUID(), embedding: [1], duration: 5, enrolledAt: Date())
        let voiceprint = Voiceprint(id: "v1", name: "Bob", samples: [sample])

        try TranscriptionService.rerenderTranscript(at: session.url, voiceprints: [voiceprint])

        #expect(try String(contentsOf: session.transcriptText, encoding: .utf8).contains("] Bob: Hi"))
    }

    @Test func loadSpeakersIsEmptyWhenAbsent() throws {
        let session = try temporarySession()
        defer { try? FileManager.default.removeItem(at: session.url) }
        #expect(try session.loadSpeakers().isEmpty)
    }

    @Test func speakersOverlayRoundTrips() throws {
        let session = try temporarySession()
        defer { try? FileManager.default.removeItem(at: session.url) }

        let overlay = [
            "speaker1": SessionSpeaker(voiceprintID: "v1", nameOverride: "Alice", embedding: [0.5, 0.25], duration: 4),
        ]
        try session.writeSpeakers(overlay)
        #expect(try session.loadSpeakers() == overlay)
    }
}
