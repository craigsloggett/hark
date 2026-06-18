import Foundation

/// One diarized speaker turn on the system-audio timeline, normalized from FluidAudio's
/// segment (seconds as `Double`, `speakerId` kept opaque).
struct DiarizationTurn: Equatable {
    let start: Double
    let end: Double
    let speakerId: String
}

/// Turns diarization output into stable speaker labels and attributes transcribed
/// utterances to speakers. Pure logic with no dependency on the diarization model,
/// so the whole thing is unit-testable without downloading or running CoreML.
enum SpeakerAttribution {
    /// Assigns each distinct diarization `speakerId` a 1-based remote `Speaker` in the
    /// order speakers first appear on the timeline, so "Speaker 1" is whoever spoke first.
    /// - Parameter turns: diarization turns; sorted by start internally.
    /// - Returns: a map from raw `speakerId` to its `Speaker.remote` label.
    static func remoteSpeakers(for turns: [DiarizationTurn]) -> [String: Speaker] {
        var speakers: [String: Speaker] = [:]
        var nextIndex = 1
        for turn in turns.sorted(by: { $0.start < $1.start }) where speakers[turn.speakerId] == nil {
            speakers[turn.speakerId] = .remote(nextIndex)
            nextIndex += 1
        }
        return speakers
    }

    /// Attributes one transcribed utterance to a speaker by maximum temporal overlap,
    /// falling back to the nearest turn by midpoint when nothing overlaps (the utterance
    /// landed in a diarization gap).
    /// - Returns: the winning `Speaker`, or `nil` when there are no turns to attribute to.
    static func speaker(
        forUtteranceFrom start: Double,
        to end: Double,
        among turns: [DiarizationTurn],
        using speakers: [String: Speaker]
    ) -> Speaker? {
        guard !turns.isEmpty else { return nil }

        var best: (speakerId: String, overlap: Double)?
        for turn in turns {
            let overlap = max(0, min(end, turn.end) - max(start, turn.start))
            if overlap > (best?.overlap ?? 0) {
                best = (turn.speakerId, overlap)
            }
        }
        if let best {
            return speakers[best.speakerId]
        }

        // No overlap: pick the turn whose midpoint is nearest the utterance's.
        let midpoint = (start + end) / 2
        let nearest = turns.min { lhs, rhs in
            abs((lhs.start + lhs.end) / 2 - midpoint) < abs((rhs.start + rhs.end) / 2 - midpoint)
        }
        return nearest.flatMap { speakers[$0.speakerId] }
    }
}
