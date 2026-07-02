import Foundation

/// One recording in the browser list, titled by its user-assigned name when it has one, otherwise by
/// when it was recorded.
struct SessionSummary: Identifiable, Hashable {
    let url: URL
    let date: Date
    var metadata = SessionMetadata()

    var id: URL {
        url
    }

    var name: String? {
        metadata.name
    }

    var tags: [String] {
        metadata.tags
    }

    var dateLabel: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var title: String {
        name ?? dateLabel
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
                // A corrupt metadata file degrades to no name rather than dropping the session.
                let metadata = (try? Session(url: url).loadMetadata()) ?? SessionMetadata()
                return SessionSummary(url: url, date: date, metadata: metadata)
            }
            .sorted { $0.date > $1.date }
    }

    /// Updates one row's metadata in place, so an edit doesn't rebuild the list or disturb selection.
    func updateMetadata(_ metadata: SessionMetadata, for url: URL) {
        guard let index = sessions.firstIndex(where: { $0.url == url }) else { return }
        sessions[index].metadata = metadata
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
