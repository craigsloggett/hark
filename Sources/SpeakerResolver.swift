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

/// Resolves a session speaker's display state from a fixed overlay and voiceprint snapshot: the
/// single source of truth for names, chip bindings, tentative matches, and grouping keys shared by
/// the chat, the transcript rendering, and the People roster.
struct SpeakerResolver {
    let overlay: [String: SessionSpeaker]
    let voiceprints: [String: Voiceprint]
    /// Distances above this (up to the match threshold) read as tentative, "Likely <name>".
    let likelyAbove: Float

    init(
        overlay: [String: SessionSpeaker],
        voiceprints: [String: Voiceprint],
        likelyAbove: Float = Float(Preferences.speakerConfidentMatchThreshold)
    ) {
        self.overlay = overlay
        self.voiceprints = voiceprints
        self.likelyAbove = likelyAbove
    }

    /// The name to show for a token, or `nil` when the speaker is unlabeled (a dashed chip that still
    /// reads "Speaker N"). Precedence: the transcript override, then the bound voiceprint's live name
    /// (following merge redirects), then `nil`.
    func name(for token: String) -> String? {
        if let override = overlay[token]?.nameOverride, !override.isEmpty {
            return override
        }
        guard let id = overlay[token]?.voiceprintID else { return nil }
        return Voiceprint.survivor(of: id, in: voiceprints)?.name
    }

    /// Token to display name for every speaker that resolves to one, feeding `Transcript.plainText(names:)`.
    func names() -> [String: String] {
        overlay.keys.reduce(into: [:]) { result, token in
            result[token] = name(for: token)
        }
    }

    /// Classifies a token's editing state so the chip and popover offer the right actions. A binding
    /// to a since-forgotten voiceprint resolves to nothing, so it degrades to its label or positional.
    func binding(for token: String) -> SpeakerBinding {
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
    func isLikelyMatch(for token: String) -> Bool {
        guard let speaker = overlay[token], !speaker.confirmed,
              (speaker.nameOverride ?? "").isEmpty,
              let id = speaker.voiceprintID,
              let distance = speaker.matchDistance,
              Voiceprint.survivor(of: id, in: voiceprints)?.name != nil
        else { return false }
        return distance > likelyAbove
    }

    /// The key that groups turns and colors chips: the bound voiceprint (following merge redirects,
    /// so tokens merged elsewhere still collapse), else the token itself.
    func identityKey(for token: String) -> String {
        guard let id = overlay[token]?.voiceprintID else { return token }
        return Voiceprint.survivor(of: id, in: voiceprints)?.id ?? id
    }
}
