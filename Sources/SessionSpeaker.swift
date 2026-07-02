import Foundation

/// A session speaker's persisted state in `speakers.json`, keyed by on-disk token. It separates a
/// transcript-only display override from the bound cross-session voiceprint identity, and carries the
/// diarized centroid so the speaker can be enrolled or split into a new voiceprint from a past session.
struct SessionSpeaker: Equatable {
    /// The bound cross-session identity; `nil` for a positional-only speaker that never matched or enrolled.
    var voiceprintID: String?
    /// A transcript-only label, preferred over the voiceprint's name and never written back to it.
    var nameOverride: String?
    /// The diarized mean embedding, persisted so a past session can enroll or split a new voiceprint.
    var embedding: Embedding?
    /// This speaker's diarized speech, the duration of the enrollment sample built from `embedding`.
    var duration: Float?
    /// The cosine distance of the auto-match that bound `voiceprintID`, so a borderline match can be
    /// shown as tentative ("Likely <name>"). `nil` for a positional speaker or a user-set binding.
    var matchDistance: Float?
    /// Whether the user has confirmed or manually set the binding, so it is shown plainly rather than
    /// as a tentative auto-match.
    var confirmed: Bool

    init(
        voiceprintID: String? = nil,
        nameOverride: String? = nil,
        matchDistance: Float? = nil,
        confirmed: Bool = false,
        embedding: Embedding? = nil,
        duration: Float? = nil
    ) {
        self.voiceprintID = voiceprintID
        self.nameOverride = nameOverride
        self.matchDistance = matchDistance
        self.confirmed = confirmed
        self.embedding = embedding
        self.duration = duration
    }

    /// Binds to a saved voice as a deliberate user choice: the transcript label and any tentative
    /// match state give way to the confirmed identity.
    mutating func bind(to voiceprintID: String) {
        self.voiceprintID = voiceprintID
        nameOverride = nil
        matchDistance = nil
        confirmed = true
    }
}

extension SessionSpeaker: Codable {
    private enum CodingKeys: String, CodingKey {
        case voiceprintID, nameOverride, matchDistance, confirmed, embedding, duration
        case id, name // Legacy `{id, name}` overlay shape.
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voiceprintID = try container.decodeIfPresent(String.self, forKey: .voiceprintID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        nameOverride = try container.decodeIfPresent(String.self, forKey: .nameOverride)
        matchDistance = try container.decodeIfPresent(Float.self, forKey: .matchDistance)
        confirmed = try container.decodeIfPresent(Bool.self, forKey: .confirmed) ?? false
        // A stored embedding of the wrong size degrades to none rather than failing the whole overlay.
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding).flatMap { Embedding($0) }
        duration = try container.decodeIfPresent(Float.self, forKey: .duration)
        // Legacy `name` was a snapshot of the voiceprint's name; dropped so the live voiceprint governs.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(voiceprintID, forKey: .voiceprintID)
        try container.encodeIfPresent(nameOverride, forKey: .nameOverride)
        try container.encodeIfPresent(matchDistance, forKey: .matchDistance)
        if confirmed {
            try container.encode(confirmed, forKey: .confirmed)
        }
        try container.encodeIfPresent(embedding, forKey: .embedding)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}
