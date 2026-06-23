@testable import hark
import Testing

struct DiarizedTimelineTests {
    private static let twoSpeakers = DiarizedTimeline(turns: [
        DiarizationTurn(start: 0, end: 2, speakerId: "A"),
        DiarizationTurn(start: 2, end: 10, speakerId: "B"),
    ])

    // MARK: Numbering

    @Test func numbersSpeakersByFirstAppearance() {
        // "B" comes first in the array, but "A" speaks earlier, so "A" is Speaker 1.
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 5, end: 6, speakerId: "B"),
            DiarizationTurn(start: 0, end: 1, speakerId: "A"),
            DiarizationTurn(start: 1, end: 2, speakerId: "B"),
        ])
        #expect(timeline.speaker(at: 0.5) == .remote(1))
        #expect(timeline.speaker(at: 5.5) == .remote(2))
    }

    @Test func mapsSingleSpeakerToSpeakerOne() {
        let timeline = DiarizedTimeline(turns: [DiarizationTurn(start: 0, end: 4, speakerId: "X")])
        #expect(timeline.speaker(at: 2) == .remote(1))
    }

    // MARK: Attribution

    @Test func attributesPointInsideTurn() {
        #expect(Self.twoSpeakers.speaker(at: 1) == .remote(1))
        #expect(Self.twoSpeakers.speaker(at: 5) == .remote(2))
    }

    @Test func snapsPointInGapToNearestTurn() {
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 0, end: 2, speakerId: "A"),
            DiarizationTurn(start: 8, end: 10, speakerId: "B"),
        ])
        // 5.5 is in the gap; nearer B's midpoint (9) than A's (1).
        #expect(timeline.speaker(at: 5.5) == .remote(2))
        // 3 is in the gap; nearer A's midpoint (1) than B's (9).
        #expect(timeline.speaker(at: 3) == .remote(1))
    }

    @Test func breaksMidpointTiesByEarliestTurn() {
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 0, end: 2, speakerId: "A"),
            DiarizationTurn(start: 8, end: 10, speakerId: "B"),
        ])
        // 5 is equidistant from both midpoints (1 and 9); the earlier turn wins.
        #expect(timeline.speaker(at: 5) == .remote(1))
    }

    @Test func returnsNilWhenNoTurns() {
        #expect(DiarizedTimeline(turns: []).speaker(at: 0) == nil)
    }
}
