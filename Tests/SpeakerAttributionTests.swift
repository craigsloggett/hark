@testable import hark
import Testing

struct SpeakerAttributionTests {
    // MARK: - remoteSpeakers

    @Test func numbersSpeakersByFirstAppearance() {
        // "B" comes first in the array, but "A" speaks earlier, so "A" is Speaker 1.
        let turns = [
            DiarizationTurn(start: 5, end: 6, speakerId: "B"),
            DiarizationTurn(start: 0, end: 1, speakerId: "A"),
            DiarizationTurn(start: 1, end: 2, speakerId: "B"),
        ]
        let speakers = SpeakerAttribution.remoteSpeakers(for: turns)
        #expect(speakers == ["A": .remote(1), "B": .remote(2)])
    }

    @Test func mapsSingleSpeakerToSpeakerOne() {
        let turns = [DiarizationTurn(start: 0, end: 4, speakerId: "X")]
        #expect(SpeakerAttribution.remoteSpeakers(for: turns) == ["X": .remote(1)])
    }

    @Test func mapsNoTurnsToEmpty() {
        #expect(SpeakerAttribution.remoteSpeakers(for: []).isEmpty)
    }

    // MARK: - speaker(forUtterance…)

    private static let twoSpeakers = [
        DiarizationTurn(start: 0, end: 2, speakerId: "A"),
        DiarizationTurn(start: 2, end: 10, speakerId: "B"),
    ]

    @Test func attributesByMaxOverlap() {
        // 1…4 overlaps A by 1s and B by 2s, so B (Speaker 2) wins.
        let speakers = SpeakerAttribution.remoteSpeakers(for: Self.twoSpeakers)
        let speaker = SpeakerAttribution.speaker(
            forUtteranceFrom: 1, to: 4, among: Self.twoSpeakers, using: speakers
        )
        #expect(speaker == .remote(2))
    }

    @Test func attributesSpanningUtteranceToDominantSpeaker() {
        let turns = [
            DiarizationTurn(start: 0, end: 3, speakerId: "A"),
            DiarizationTurn(start: 3, end: 10, speakerId: "B"),
        ]
        let speakers = SpeakerAttribution.remoteSpeakers(for: turns)
        let speaker = SpeakerAttribution.speaker(
            forUtteranceFrom: 0, to: 10, among: turns, using: speakers
        )
        #expect(speaker == .remote(2)) // B covers 7s vs A's 3s
    }

    @Test func fallsBackToNearestMidpointOnZeroOverlap() {
        let turns = [
            DiarizationTurn(start: 0, end: 2, speakerId: "A"),
            DiarizationTurn(start: 8, end: 10, speakerId: "B"),
        ]
        let speakers = SpeakerAttribution.remoteSpeakers(for: turns)
        // 5…6 (midpoint 5.5) overlaps neither; nearer B's midpoint (9) than A's (1).
        let speaker = SpeakerAttribution.speaker(
            forUtteranceFrom: 5, to: 6, among: turns, using: speakers
        )
        #expect(speaker == .remote(2))
    }

    @Test func breaksMidpointTiesByEarliestTurn() {
        let turns = [
            DiarizationTurn(start: 0, end: 2, speakerId: "A"),
            DiarizationTurn(start: 8, end: 10, speakerId: "B"),
        ]
        let speakers = SpeakerAttribution.remoteSpeakers(for: turns)
        // 4…6 (midpoint 5) is equidistant from both midpoints; the earlier turn wins.
        let speaker = SpeakerAttribution.speaker(
            forUtteranceFrom: 4, to: 6, among: turns, using: speakers
        )
        #expect(speaker == .remote(1))
    }

    @Test func returnsNilWhenNoTurns() {
        #expect(SpeakerAttribution.speaker(forUtteranceFrom: 0, to: 1, among: [], using: [:]) == nil)
    }
}
