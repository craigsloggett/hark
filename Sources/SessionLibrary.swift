import Foundation

/// One recording in the browser list, titled by when it was recorded (sessions have no name).
struct SessionSummary: Identifiable, Hashable {
    let url: URL
    let date: Date

    var id: URL {
        url
    }

    var title: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A loaded session: its positional transcript segments and the editable speaker overlay.
struct SessionDetail {
    let url: URL
    let segments: [TranscriptSegment]
    var overlay: [String: SessionSpeaker]
}

/// Lists transcribed recording sessions from the Documents folder and loads one on demand.
@MainActor
@Observable
final class SessionLibrary {
    private(set) var sessions: [SessionSummary] = []

    /// Rebuilds the list from the `hark-<timestamp>` folders that hold a transcript, newest first.
    /// A session without `transcript.json` (recorded but not yet transcribed) is left out.
    func reload() {
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            sessions = []
            return
        }
        let folders = (try? manager.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        sessions = folders
            .compactMap { url -> SessionSummary? in
                guard let date = AudioRecorder.date(from: url.lastPathComponent),
                      manager.fileExists(atPath: Session(url: url).transcriptJSON.path)
                else { return nil }
                return SessionSummary(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Loads a session's positional segments and speaker overlay.
    func loadDetail(_ url: URL) throws -> SessionDetail {
        let session = Session(url: url)
        let segments = try JSONDecoder().decode(
            [TranscriptSegment].self, from: Data(contentsOf: session.transcriptJSON)
        )
        return try SessionDetail(url: url, segments: segments, overlay: session.loadSpeakers())
    }
}
