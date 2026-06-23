@testable import hark
import Testing

struct TimedTokenTests {
    /// Resolver placing the boundary at t = 1.5: earlier tokens are Speaker 1, later ones Speaker 2.
    private static func twoSpeakers(_ midpoint: Double) -> Speaker {
        midpoint < 1.5 ? .remote(1) : .remote(2)
    }

    // MARK: Text reconstruction

    @Test func joinsLeadingSpaceTokensIntoWords() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " Hello"),
            TimedToken(start: 1, end: 2, text: " world"),
        ]
        let segments = tokens.segments(resolving: { _ in .you }, gap: 0.6)
        #expect(segments.count == 1)
        #expect(segments.first?.text == "Hello world")
    }

    @Test func joinsSubwordContinuationsWithoutSpaces() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " wonder"),
            TimedToken(start: 1, end: 2, text: "ful"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).first?.text == "wonderful")
    }

    @Test func spansTheRunStartToEnd() {
        let tokens = [
            TimedToken(start: 0.4, end: 1, text: " a"),
            TimedToken(start: 1, end: 2.7, text: " b"),
        ]
        let segment = tokens.segments(resolving: { _ in .you }, gap: 0.6).first
        #expect(segment?.start == 0.4)
        #expect(segment?.end == 2.7)
    }

    // MARK: Breaking

    @Test func breaksWhenSilenceExceedsGap() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " Hello"),
            TimedToken(start: 5, end: 6, text: " world"),
        ]
        let segments = tokens.segments(resolving: { _ in .you }, gap: 0.6)
        #expect(segments.map(\.text) == ["Hello", "world"])
        #expect(segments.map(\.start) == [0, 5])
    }

    @Test func keepsRunWhenSilenceWithinGap() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " Hello"),
            TimedToken(start: 1.1, end: 2, text: " world"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).count == 1)
    }

    @Test func breaksWhenSpeakerChanges() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " A"),
            TimedToken(start: 1, end: 2, text: " B"),
        ]
        let segments = tokens.segments(resolving: Self.twoSpeakers, gap: 5)
        #expect(segments.map(\.speaker) == [.remote(1), .remote(2)])
        #expect(segments.map(\.text) == ["A", "B"])
    }

    @Test func overlappingTokensDoNotBreak() {
        // Chunk seams can emit tokens whose start precedes the previous token's end.
        let tokens = [
            TimedToken(start: 0, end: 1.5, text: " a"),
            TimedToken(start: 1.0, end: 2, text: " b"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).count == 1)
    }

    // MARK: Edges

    @Test func emptyInputProducesNoSegments() {
        #expect([TimedToken]().segments(resolving: { _ in .you }, gap: 0.6).isEmpty)
    }

    @Test func singleTokenProducesOneSegment() {
        let segments = [TimedToken(start: 0, end: 1, text: " hi")].segments(resolving: { _ in .you }, gap: 0.6)
        #expect(segments == [TranscriptSegment(start: 0, end: 1, speaker: .you, text: "hi")])
    }

    @Test func whitespaceOnlyRunIsDropped() {
        let tokens = [TimedToken(start: 0, end: 1, text: " ")]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).isEmpty)
    }

    // MARK: Punctuation

    @Test func trailingPunctuationAfterGapJoinsPreviousSentence() {
        // A lone period emitted after a long pause terminates the prior sentence; the gap still
        // separates the next utterance rather than being absorbed by the stray token.
        let tokens = [
            TimedToken(start: 0, end: 1, text: " keep"),
            TimedToken(start: 1, end: 2, text: " you"),
            TimedToken(start: 9, end: 9.1, text: "."),
            TimedToken(start: 9.1, end: 10, text: " Okay"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).map(\.text) == ["keep you.", "Okay"])
    }

    @Test func standalonePunctuationProducesNoSegment() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " hello"),
            TimedToken(start: 5, end: 5.1, text: "."),
            TimedToken(start: 12, end: 13, text: " world"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).map(\.text) == ["hello.", "world"])
    }

    @Test func leadingPunctuationIsDropped() {
        let tokens = [
            TimedToken(start: 0, end: 0.1, text: "."),
            TimedToken(start: 0.2, end: 1, text: " hi"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).map(\.text) == ["hi"])
    }

    @Test func punctuationWithinARunStaysAttached() {
        let tokens = [
            TimedToken(start: 0, end: 1, text: " yes"),
            TimedToken(start: 1, end: 1.1, text: ","),
            TimedToken(start: 1.1, end: 2, text: " please"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).map(\.text) == ["yes, please"])
    }

    @Test func subwordContinuationNeverSplitsOnGap() {
        // "we'" and "re" are pieces of one word; a timing gap between them must not split it.
        let tokens = [
            TimedToken(start: 0, end: 1, text: " we'"),
            TimedToken(start: 2, end: 3, text: "re"),
            TimedToken(start: 3, end: 4, text: " here"),
        ]
        #expect(tokens.segments(resolving: { _ in .you }, gap: 0.6).map(\.text) == ["we're here"])
    }
}
