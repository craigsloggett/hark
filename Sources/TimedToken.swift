import Foundation

/// One transcribed token with its place on a track's timeline. `text` carries the leading-space
/// word-boundary convention from the ASR tokenizer, so a run of tokens joins straight into
/// readable text with no inserted separators.
struct TimedToken: Equatable {
    let start: Double
    let end: Double
    let text: String
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

        func flush() {
            guard let runSpeaker, let first = run.first, let last = run.last else { return }
            let text = run.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            // A run of pure word-boundary tokens trims to nothing; it carries no utterance.
            guard !text.isEmpty else { return }
            segments.append(TranscriptSegment(start: first.start, end: last.end, speaker: runSpeaker, text: text))
        }

        for token in self {
            let tokenSpeaker = speaker((token.start + token.end) / 2)
            // Tokens can overlap at chunk seams, so a negative gap must never start a new run.
            let silent = run.last.map { token.start - $0.end > gap } ?? false
            if runSpeaker != tokenSpeaker || silent {
                flush()
                run = []
                runSpeaker = tokenSpeaker
            }
            run.append(token)
        }
        flush()
        return segments
    }
}
