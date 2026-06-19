import Foundation

enum Speaker: Equatable {
    case you
    case remote(Int) // 1-based: `.remote(1)` is "Speaker 1"

    var label: String {
        switch self {
        case .you: "You"
        case let .remote(index): "Speaker \(index)"
        }
    }
}

extension Speaker: Codable {
    private enum DecodingFailure: Error {
        case unrecognizedToken(String)
    }

    /// Encodes as a single token (`you`, `speaker1`, `speaker2`, etc.).
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .you: try container.encode("you")
        case let .remote(index): try container.encode("speaker\(index)")
        }
    }

    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        if token == "you" {
            self = .you
            return
        }
        let prefix = "speaker"
        guard token.hasPrefix(prefix), let index = Int(token.dropFirst(prefix.count)), index >= 1 else {
            throw DecodingFailure.unrecognizedToken(token)
        }
        self = .remote(index)
    }
}

/// One contiguous utterance with its place on the recording's timeline.
struct TranscriptSegment: Codable, Equatable {
    let start: Double
    let end: Double
    let speaker: Speaker
    let text: String
}

extension [TranscriptSegment] {
    /// Returns the segments moved later by `offset` seconds, used to place a track that began
    /// recording after the reference track onto the reference's timeline.
    func shifted(by offset: TimeInterval) -> [TranscriptSegment] {
        guard offset != 0 else { return self }
        return map {
            TranscriptSegment(start: $0.start + offset, end: $0.end + offset, speaker: $0.speaker, text: $0.text)
        }
    }
}

struct Transcript: Equatable {
    let segments: [TranscriptSegment]

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
