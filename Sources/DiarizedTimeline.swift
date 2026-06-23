import Foundation

struct DiarizationTurn: Equatable {
    let start: Double
    let end: Double
    let speakerId: String
}

struct DiarizedTimeline {
    private let turns: [DiarizationTurn]
    private let speakers: [String: Speaker]

    init(turns: [DiarizationTurn]) {
        let ordered = turns.sorted { $0.start < $1.start }
        var speakers: [String: Speaker] = [:]
        var nextIndex = 1
        for turn in ordered where speakers[turn.speakerId] == nil {
            speakers[turn.speakerId] = .remote(nextIndex)
            nextIndex += 1
        }
        self.turns = ordered
        self.speakers = speakers
    }

    /// Attributes one token to a speaker by the turn its `time` falls in, falling back to the
    /// nearest turn by midpoint when it lands in a diarization gap.
    /// - Returns: the containing speaker, or `nil` when the timeline has no turns.
    func speaker(at time: Double) -> Speaker? {
        guard !turns.isEmpty else { return nil }
        // `turns` is sorted by start, so the first match is the earliest-starting turn that
        // contains the time, keeping crosstalk ties consistent with the overlap path.
        if let containing = turns.first(where: { time >= $0.start && time <= $0.end }) {
            return speakers[containing.speakerId]
        }
        return nearestSpeaker(to: time)
    }

    /// The speaker of the turn whose midpoint is nearest `time`. Ties go to the earliest turn.
    private func nearestSpeaker(to time: Double) -> Speaker? {
        let nearest = turns.min { lhs, rhs in
            let lhsDistance = abs((lhs.start + lhs.end) / 2 - time)
            let rhsDistance = abs((rhs.start + rhs.end) / 2 - time)
            return lhsDistance < rhsDistance
        }
        return nearest.flatMap { speakers[$0.speakerId] }
    }
}
