import Foundation

/// Which side of the meeting a segment came from. The recording's two tracks are
/// the diarization: the microphone is the local user, system audio is everyone else.
enum Speaker: String, Codable {
    case you
    case them

    var label: String {
        switch self {
        case .you: "You"
        case .them: "Them"
        }
    }
}

/// One contiguous utterance with its place on the recording's timeline.
struct TranscriptSegment: Codable, Equatable {
    let start: Double
    let end: Double
    let speaker: Speaker
    let text: String
}

/// A meeting transcript: segments from both tracks, ordered by start time.
struct Transcript: Equatable {
    let segments: [TranscriptSegment]

    /// Readable transcript, one line per segment: `[hh:mm:ss] You: ...`.
    func plainText() -> String {
        segments
            .map { "[\(Self.timestamp($0.start))] \($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Seconds from the start of the recording as `hh:mm:ss`.
    static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Combines two tracks' segments into one transcript ordered by start time.
    static func merging(_ first: [TranscriptSegment], _ second: [TranscriptSegment]) -> Transcript {
        Transcript(segments: (first + second).sorted { $0.start < $1.start })
    }
}
