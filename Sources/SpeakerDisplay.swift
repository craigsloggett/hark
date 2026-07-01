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

    /// Whether a token is an unconfirmed auto-match far enough from certainty to be worth confirming,
    /// shown as "Likely <name>" with confirm/reject. A confirmed or user-set binding, a strong match,
    /// an unnamed voice, or a transcript label is never tentative.
    /// - Parameter likelyAbove: distances above this (up to the match threshold) read as tentative.
    static func isLikelyMatch(
        token: String,
        overlay: [String: SessionSpeaker],
        voiceprints: [String: Voiceprint],
        likelyAbove: Float
    ) -> Bool {
        guard let speaker = overlay[token], !speaker.confirmed,
              (speaker.nameOverride ?? "").isEmpty,
              let id = speaker.voiceprintID,
              let distance = speaker.matchDistance,
              Voiceprint.survivor(of: id, in: voiceprints)?.name != nil
        else { return false }
        return distance > likelyAbove
    }
}
