import Foundation

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

/// The global voice-management surface: the cross-session roster, duplicate detection, and merges that
/// span recordings (the per-session People inspector only merges speakers within one transcript).
extension LabelingModel {
    /// Every surviving saved voice, named ones first (alphabetically), then unnamed by id.
    var voices: [VoiceSummary] {
        voiceprintsByID.values
            .filter { $0.redirectID == nil }
            .map(summary(for:))
            .sorted(by: Self.voiceOrdering)
    }

    var canMergeVoices: Bool {
        voicesSelection.count == 2
    }

    func mergeSelectedVoices() async {
        guard voicesSelection.count == 2 else { return }
        let ids = Array(voicesSelection)
        await mergeVoices(ids[0], ids[1])
    }

    func mergeSuggestion(_ suggestion: DuplicateSuggestion) async {
        await mergeVoices(suggestion.primary.id, suggestion.secondary.id)
    }

    private func mergeVoices(_ first: String, _ second: String) async {
        guard first != second else { return }
        recordUndo("Merge Voices")
        let (destination, source) = canonicalMerge(first, second)
        await attempt("Merge voices") { try await SpeakerStore.shared.merge(source, into: destination) }
        voicesSelection = [destination]
        await finishEdit(reloadDatabase: true)
    }

    /// Builds a manager row summary for a voiceprint. Internal so the sibling file's
    /// `refreshDuplicateSuggestions` (which sets the `private(set)` list) can reuse it.
    func summary(for voiceprint: Voiceprint) -> VoiceSummary {
        VoiceSummary(
            id: voiceprint.id,
            name: voiceprint.name,
            sampleCount: voiceprint.samples.count,
            recordingCount: voiceUsage[voiceprint.id] ?? 0
        )
    }

    private static func voiceOrdering(_ lhs: VoiceSummary, _ rhs: VoiceSummary) -> Bool {
        switch (lhs.name, rhs.name) {
        case let (left?, right?): left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.id < rhs.id
        }
    }
}
