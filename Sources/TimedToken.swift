import Foundation

/// One transcribed token with its place on a track's timeline. `text` carries the leading-space
/// word-boundary convention from the ASR tokenizer, so a run of tokens joins straight into
/// readable text with no inserted separators.
struct TimedToken: Equatable {
    let start: Double
    let end: Double
    let text: String

    /// Whether the token carries no letters or digits (a lone `.`, `,`, etc.). Punctuation
    /// terminates the word it follows rather than marking a turn, so grouping never breaks on it.
    var isPunctuation: Bool {
        !text.contains { $0.isLetter || $0.isNumber }
    }

    /// Whether the token starts a new word. The ASR marks word starts with a leading space, so a
    /// token without one is a subword continuation that grouping must never split off mid-word.
    var startsWord: Bool {
        text.first?.isWhitespace ?? false
    }
}

extension [TimedToken] {
    /// Groups consecutive tokens into utterances, attributing each token to a speaker at its
    /// midpoint. A run breaks when the speaker changes or the silence before a token exceeds
    /// `gap`, which is how diarized turns and natural pauses become separate transcript lines.
    /// - Parameters:
    ///   - speaker: resolves the speaker for a token's midpoint time.
    ///   - gap: the inter-token silence, in seconds, that ends an utterance.
    func segments(resolving speaker: (Double) -> Speaker, gap: Double) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var run: [TimedToken] = []
        var runSpeaker: Speaker?
        // End of the last real word in the run. Silence is measured from here so a punctuation
        // token that floated forward in time can't mask the gap before the next utterance.
        var lastWordEnd: Double?

        func flush() {
            guard let attributed = runSpeaker, let first = run.first, let last = run.last else { return }
            let text = run.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            segments.append(TranscriptSegment(start: first.start, end: last.end, speaker: attributed, text: text))
        }

        for token in self {
            // Punctuation rides along with the word it follows; it never opens or closes a run and
            // is dropped when no run is open yet.
            if token.isPunctuation {
                if !run.isEmpty { run.append(token) }
                continue
            }

            // Subword continuations (no leading space) stay with the word in progress regardless
            // of any timing gap, so a word is never split across utterances.
            if !token.startsWord, !run.isEmpty {
                run.append(token)
                lastWordEnd = token.end
                continue
            }

            let tokenSpeaker = speaker((token.start + token.end) / 2)
            let silent = lastWordEnd.map { token.start - $0 > gap } ?? false
            if runSpeaker == tokenSpeaker, !silent {
                run.append(token)
                lastWordEnd = token.end
                continue
            }
            flush()
            run = [token]
            runSpeaker = tokenSpeaker
            lastWordEnd = token.end
        }
        flush()
        return segments
    }
}
