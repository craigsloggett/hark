import Foundation
@testable import hark
import Testing

struct TranscriptTests {
    // MARK: Labels and timestamps

    @Test func speakerLabelsReadAsPersonas() {
        #expect(Speaker.you.label == "You")
        #expect(Speaker.remote(1).label == "Speaker 1")
        #expect(Speaker.remote(2).label == "Speaker 2")
    }

    @Test func timestampFormatsHoursMinutesSeconds() {
        #expect(Transcript.timestamp(0) == "00:00:00")
        #expect(Transcript.timestamp(75) == "00:01:15")
        #expect(Transcript.timestamp(3661) == "01:01:01")
    }

    // MARK: Merging and shifting

    @Test func mergingOrdersSegmentsByStartTime() {
        let you = [
            TranscriptSegment(start: 0, end: 2, speaker: .you, text: "A"),
            TranscriptSegment(start: 4, end: 6, speaker: .you, text: "C"),
        ]
        let them = [
            TranscriptSegment(start: 2, end: 4, speaker: .remote(1), text: "B"),
        ]
        let merged = Transcript.merging(you, them)
        #expect(merged.segments.map(\.text) == ["A", "B", "C"])
        #expect(merged.segments.map(\.speaker) == [.you, .remote(1), .you])
    }

    @Test func shiftingMovesSegmentsLaterByOffset() {
        let them = [TranscriptSegment(start: 5, end: 6, speaker: .remote(1), text: "B")]
        let shifted = them.shifted(by: 6)
        #expect(shifted.map(\.start) == [11])
        #expect(shifted.map(\.end) == [12])
        #expect(shifted.map(\.speaker) == [.remote(1)])
    }

    @Test func zeroOffsetLeavesSegmentsUnchanged() {
        let them = [TranscriptSegment(start: 5, end: 6, speaker: .remote(1), text: "B")]
        #expect(them.shifted(by: 0) == them)
    }

    @Test func systemTrackOffsetRestoresRealOrder() {
        // The mic line was spoken before the remote reply, but the system track started 6s late,
        // so its file-relative time (5) sorts ahead of the mic line (10) until the offset is applied.
        let you = [TranscriptSegment(start: 10, end: 12, speaker: .you, text: "A")]
        let them = [TranscriptSegment(start: 5, end: 6, speaker: .remote(1), text: "B")]
        let merged = Transcript.merging(you, them.shifted(by: 6))
        #expect(merged.segments.map(\.speaker) == [.you, .remote(1)])
        #expect(merged.segments.map(\.text) == ["A", "B"])
    }

    // MARK: Plain text

    @Test func plainTextRendersTimestampedSpeakerLines() {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 3, end: 5, speaker: .you, text: "Hello"),
            TranscriptSegment(start: 65, end: 67, speaker: .remote(1), text: "Hi there"),
            TranscriptSegment(start: 70, end: 72, speaker: .remote(2), text: "Hey"),
        ])
        let expected = """
        [00:00:03] You: Hello
        [00:01:05] Speaker 1: Hi there
        [00:01:10] Speaker 2: Hey
        """
        #expect(transcript.plainText() == expected)
    }

    @Test func plainTextPrefersNamesOverPositionalLabels() {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 0, end: 1, speaker: .you, text: "Morning"),
            TranscriptSegment(start: 2, end: 3, speaker: .remote(1), text: "Hi"),
            TranscriptSegment(start: 4, end: 5, speaker: .remote(2), text: "Hey"),
        ])
        // Only speaker1 is named; `you` and the unnamed speaker2 fall back to their labels.
        let expected = """
        [00:00:00] You: Morning
        [00:00:02] Alice: Hi
        [00:00:04] Speaker 2: Hey
        """
        #expect(transcript.plainText(names: ["speaker1": "Alice"]) == expected)
    }

    // MARK: Codable

    @Test func segmentRoundTripsThroughJSON() throws {
        let segment = TranscriptSegment(start: 1.5, end: 2.5, speaker: .remote(3), text: #"Quote "x""#)
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(decoded == segment)
    }

    @Test func speakerInitFromTokenInvertsToken() {
        #expect(Speaker(token: "you") == .you)
        #expect(Speaker(token: "speaker3") == .remote(3))
        #expect(Speaker(token: "them") == nil)
        #expect(Speaker(token: "speaker0") == nil)
        for speaker in [Speaker.you, .remote(1), .remote(12)] {
            #expect(Speaker(token: speaker.token) == speaker)
        }
    }

    @Test func segmentEncodesSpeakerAsToken() throws {
        let you = try JSONEncoder().encode(TranscriptSegment(start: 0, end: 1, speaker: .you, text: "Hi"))
        #expect(try #require(String(bytes: you, encoding: .utf8)).contains("\"speaker\":\"you\""))

        let remote = try JSONEncoder().encode(TranscriptSegment(start: 0, end: 1, speaker: .remote(2), text: "Hi"))
        #expect(try #require(String(bytes: remote, encoding: .utf8)).contains("\"speaker\":\"speaker2\""))
    }

    @Test func decodingRejectsUnknownSpeakerToken() {
        let unknown = Data(#"{"start":0,"end":1,"speaker":"them","text":"Hi"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TranscriptSegment.self, from: unknown)
        }
        let zero = Data(#"{"start":0,"end":1,"speaker":"speaker0","text":"Hi"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TranscriptSegment.self, from: zero)
        }
    }
}
