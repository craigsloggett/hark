/// A speaker's resolved cross-session identity, the result of matching one session's clusters against
/// the voiceprint database.
struct SpeakerIdentity: Codable, Equatable {
    let id: String
    let name: String?
    /// The match's cosine distance, so the labeling UI can flag a borderline auto-match. `nil` for a
    /// freshly enrolled voice, which is new rather than matched.
    let distance: Float?
}
