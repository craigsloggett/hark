import Foundation

/// The on-disk layout of one recording session, a folder holding the two audio tracks and the
/// transcript outputs. Both the recorder (writer) and the transcription service (reader) derive
/// their paths here, so the layout has a single source of truth.
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

    /// The `speakers.json` overlay keyed by speaker token, or empty when the session has none (a
    /// mic-only recording never writes it).
    func loadSpeakers() throws -> [String: SessionSpeaker] {
        guard FileManager.default.fileExists(atPath: speakers.path) else { return [:] }
        return try JSONDecoder().decode([String: SessionSpeaker].self, from: Data(contentsOf: speakers))
    }

    func writeSpeakers(_ overlay: [String: SessionSpeaker]) throws {
        try overlay.writeJSON(to: speakers)
    }
}
