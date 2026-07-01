/// One saved voice in the global manager: its name (or unnamed), sample count, and how many
/// recordings use it.
struct VoiceSummary: Identifiable, Equatable {
    let id: String
    let name: String?
    let sampleCount: Int
    let recordingCount: Int

    var isNamed: Bool {
        name != nil
    }

    var displayName: String {
        name ?? "Unnamed voice"
    }
}

/// A pair of saved voices that sound alike, offered for one-tap merging. `primary` is the merge
/// target, the named side when only one is named.
struct DuplicateSuggestion: Identifiable, Equatable {
    let primary: VoiceSummary
    let secondary: VoiceSummary
    let distance: Float

    var id: String {
        primary.id + "|" + secondary.id
    }
}
