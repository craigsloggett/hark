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

    func loadDetail(_ url: URL) throws -> SessionDetail {
        let session = Session(url: url)
        return try SessionDetail(url: url, segments: session.loadSegments(), overlay: session.loadSpeakers())
    }

    /// Counts, per surviving voiceprint id, how many recordings bind at least one speaker to it, so the
    /// People inspector can show where a saved voice has been heard. Follows merge redirects, and a
    /// session whose overlay can't be read is skipped rather than failing the whole tally.
    func voiceUsage(resolving voiceprints: [String: Voiceprint]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for summary in sessions {
            guard let overlay = try? Session(url: summary.url).loadSpeakers() else { continue }
            let survivors = Set(overlay.values.compactMap { speaker -> String? in
                guard let id = speaker.voiceprintID else { return nil }
                return Voiceprint.survivor(of: id, in: voiceprints)?.id
            })
            for id in survivors {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }
}
