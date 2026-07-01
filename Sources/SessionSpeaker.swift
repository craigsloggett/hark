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
    var embedding: [Float]?
    /// This speaker's diarized speech, the duration of the enrollment sample built from `embedding`.
    var duration: Float?

    init(voiceprintID: String? = nil, nameOverride: String? = nil, embedding: [Float]? = nil, duration: Float? = nil) {
        self.voiceprintID = voiceprintID
        self.nameOverride = nameOverride
        self.embedding = embedding
        self.duration = duration
    }
}

extension SessionSpeaker: Codable {
    private enum CodingKeys: String, CodingKey {
        case voiceprintID, nameOverride, embedding, duration
        case id, name // Legacy `{id, name}` overlay shape.
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voiceprintID = try container.decodeIfPresent(String.self, forKey: .voiceprintID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        nameOverride = try container.decodeIfPresent(String.self, forKey: .nameOverride)
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
        duration = try container.decodeIfPresent(Float.self, forKey: .duration)
        // Legacy `name` was a snapshot of the voiceprint's name; dropped so the live voiceprint governs.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(voiceprintID, forKey: .voiceprintID)
        try container.encodeIfPresent(nameOverride, forKey: .nameOverride)
        try container.encodeIfPresent(embedding, forKey: .embedding)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

/// A chip's editing state, the three mutually exclusive cases the labeling UI renders and offers
/// actions for. Bound-to-a-saved-voice takes precedence over a transcript label, so a saved voice
/// shown under a custom label is still a `savedVoice`.
enum SpeakerBinding: Equatable {
    /// No label and no bound voice: a dashed "Speaker N" chip.
    case unknown
    /// A transcript-only name, not tied to any saved voice.
    case localLabel(String)
    /// Bound to a cross-session voiceprint (by its stored, pre-redirect id).
    case savedVoice(id: String)
}

/// Resolves a session speaker's display name, the single source of truth shared by the chat, the
/// transcript rendering, and the People roster.
enum SpeakerDisplay {
    /// The name to show for a token, or `nil` when the speaker is unlabeled (a dashed chip that still
    /// reads "Speaker N"). Precedence: the transcript override, then the bound voiceprint's live name
    /// (following merge redirects), then `nil`.
    static func name(
        token: String,
        overlay: [String: SessionSpeaker],
        voiceprints: [String: Voiceprint]
    ) -> String? {
        if let override = overlay[token]?.nameOverride, !override.isEmpty {
            return override
        }
        guard let id = overlay[token]?.voiceprintID else { return nil }
        return Voiceprint.survivor(of: id, in: voiceprints)?.name
    }

    /// Token to display name for every speaker that resolves to one, feeding `Transcript.plainText(names:)`.
    static func names(
        overlay: [String: SessionSpeaker],
        voiceprints: [String: Voiceprint]
    ) -> [String: String] {
        overlay.keys.reduce(into: [:]) { result, token in
            result[token] = name(token: token, overlay: overlay, voiceprints: voiceprints)
        }
    }

    /// Classifies a token's editing state so the chip and popover offer the right actions. A binding
    /// to a since-forgotten voiceprint resolves to nothing, so it degrades to its label or positional.
    static func binding(
        token: String,
        overlay: [String: SessionSpeaker],
        voiceprints: [String: Voiceprint]
    ) -> SpeakerBinding {
        let speaker = overlay[token]
        if let id = speaker?.voiceprintID, Voiceprint.survivor(of: id, in: voiceprints) != nil {
            return .savedVoice(id: id)
        }
        if let override = speaker?.nameOverride, !override.isEmpty {
            return .localLabel(override)
        }
        return .unknown
    }
}
