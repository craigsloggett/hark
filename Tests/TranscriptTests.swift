import Foundation
@testable import hark
import Testing

struct TranscriptTests {
    @Test func speakerLabelsReadAsPersonas() {
        #expect(Speaker.you.label == "You")
        #expect(Speaker.them.label == "Them")
    }

    @Test func timestampFormatsHoursMinutesSeconds() {
        #expect(Transcript.timestamp(0) == "00:00:00")
        #expect(Transcript.timestamp(75) == "00:01:15")
        #expect(Transcript.timestamp(3661) == "01:01:01")
    }

    @Test func mergingOrdersSegmentsByStartTime() {
        let you = [
            TranscriptSegment(start: 0, end: 2, speaker: .you, text: "A"),
            TranscriptSegment(start: 4, end: 6, speaker: .you, text: "C"),
        ]
        let them = [
            TranscriptSegment(start: 2, end: 4, speaker: .them, text: "B"),
        ]
        let merged = Transcript.merging(you, them)
        #expect(merged.segments.map(\.text) == ["A", "B", "C"])
        #expect(merged.segments.map(\.speaker) == [.you, .them, .you])
    }

    @Test func plainTextRendersTimestampedSpeakerLines() {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 3, end: 5, speaker: .you, text: "Hello"),
            TranscriptSegment(start: 65, end: 67, speaker: .them, text: "Hi there"),
        ])
        let expected = """
        [00:00:03] You: Hello
        [00:01:05] Them: Hi there
        """
        #expect(transcript.plainText() == expected)
    }

    @Test func segmentRoundTripsThroughJSON() throws {
        let segment = TranscriptSegment(start: 1.5, end: 2.5, speaker: .them, text: #"Quote "x""#)
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(decoded == segment)
    }

    @Test func segmentEncodesSpeakerAsLowercasedToken() throws {
        let data = try JSONEncoder().encode(TranscriptSegment(start: 0, end: 1, speaker: .you, text: "Hi"))
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(json.contains("\"speaker\":\"you\""))
    }
}
