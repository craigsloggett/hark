import Foundation

/// The on-disk layout of one recording session, a folder holding the two audio tracks, the
/// transcript outputs, and the user-assigned metadata. Both the recorder (writer) and the
/// transcription service (reader) derive their paths here, so the layout has a single source of truth.
struct Session {
    let url: URL

    var mic: URL {
        url.appendingPathComponent("mic.wav")
    }

    var system: URL {
        url.appendingPathComponent("system.wav")
    }

    var transcriptText: URL {
        url.appendingPathComponent("transcript.txt")
    }

    var transcriptJSON: URL {
        url.appendingPathComponent("transcript.json")
    }

    var speakers: URL {
        url.appendingPathComponent("speakers.json")
    }

    var metadata: URL {
        url.appendingPathComponent("metadata.json")
    }

    /// The positional transcript segments stored in `transcript.json`.
    func loadSegments() throws -> [TranscriptSegment] {
        try JSONDecoder().decode([TranscriptSegment].self, from: Data(contentsOf: transcriptJSON))
    }

    /// The `speakers.json` overlay keyed by speaker token, or empty when the session has none (a
    /// mic-only recording never writes it).
    func loadSpeakers() throws -> [String: SessionSpeaker] {
        guard FileManager.default.fileExists(atPath: speakers.path) else { return [:] }
        return try JSONDecoder().decode([String: SessionSpeaker].self, from: Data(contentsOf: speakers))
    }

    func writeSpeakers(_ overlay: [String: SessionSpeaker]) throws {
        try overlay.writeJSON(to: speakers)
    }

    /// The user-assigned name and tags in `metadata.json`, or empty when the session has none (a
    /// session the user never customized never writes it).
    func loadMetadata() throws -> SessionMetadata {
        guard FileManager.default.fileExists(atPath: metadata.path) else { return SessionMetadata() }
        return try JSONDecoder().decode(SessionMetadata.self, from: Data(contentsOf: metadata))
    }

    func writeMetadata(_ metadata: SessionMetadata) throws {
        try metadata.writeJSON(to: self.metadata)
    }
}
