@testable import hark
import Testing

struct DiarizedTimelineTests {
    // MARK: Numbering

    @Test func numbersSpeakersByFirstAppearance() {
        // "B" comes first in the array, but "A" speaks earlier, so "A" is Speaker 1.
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 5, end: 6, speakerId: "B"),
            DiarizationTurn(start: 0, end: 1, speakerId: "A"),
            DiarizationTurn(start: 1, end: 2, speakerId: "B"),
        ])
        #expect(timeline.speaker(forUtteranceFrom: 0, to: 1) == .remote(1))
        #expect(timeline.speaker(forUtteranceFrom: 5, to: 6) == .remote(2))
    }

    @Test func mapsSingleSpeakerToSpeakerOne() {
        let timeline = DiarizedTimeline(turns: [DiarizationTurn(start: 0, end: 4, speakerId: "X")])
        #expect(timeline.speaker(forUtteranceFrom: 1, to: 2) == .remote(1))
    }

    // MARK: Attribution

    private static let twoSpeakers = DiarizedTimeline(turns: [
        DiarizationTurn(start: 0, end: 2, speakerId: "A"),
        DiarizationTurn(start: 2, end: 10, speakerId: "B"),
    ])

    @Test func attributesByMaxOverlap() {
        // 1…4 overlaps A by 1s and B by 2s, so B (Speaker 2) wins.
        #expect(Self.twoSpeakers.speaker(forUtteranceFrom: 1, to: 4) == .remote(2))
    }

    @Test func attributesSpanningUtteranceToDominantSpeaker() {
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 0, end: 3, speakerId: "A"),
            DiarizationTurn(start: 3, end: 10, speakerId: "B"),
        ])
        // B covers 7s vs A's 3s.
        #expect(timeline.speaker(forUtteranceFrom: 0, to: 10) == .remote(2))
    }

    @Test func fallsBackToNearestMidpointOnZeroOverlap() {
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 0, end: 2, speakerId: "A"),
            DiarizationTurn(start: 8, end: 10, speakerId: "B"),
        ])
        // 5…6 (midpoint 5.5) overlaps neither; nearer B's midpoint (9) than A's (1).
        #expect(timeline.speaker(forUtteranceFrom: 5, to: 6) == .remote(2))
    }

    @Test func breaksMidpointTiesByEarliestTurn() {
        let timeline = DiarizedTimeline(turns: [
            DiarizationTurn(start: 0, end: 2, speakerId: "A"),
            DiarizationTurn(start: 8, end: 10, speakerId: "B"),
        ])
        // 4…6 (midpoint 5) is equidistant from both midpoints; the earlier turn wins.
        #expect(timeline.speaker(forUtteranceFrom: 4, to: 6) == .remote(1))
    }

    @Test func returnsNilWhenNoTurns() {
        #expect(DiarizedTimeline(turns: []).speaker(forUtteranceFrom: 0, to: 1) == nil)
    }
}
