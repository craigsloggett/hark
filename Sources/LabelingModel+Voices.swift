import Foundation

/// The global voice-management surface: the cross-session roster, duplicate detection, and merges that
/// span recordings (the per-session People inspector only merges speakers within one transcript).
extension LabelingModel {
    /// Every surviving saved voice, named ones first (alphabetically), then unnamed by id.
    var voices: [VoiceSummary] {
        voiceprintsByID.values
            .filter { !$0.isTombstone }
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

    private func mergeVoices(_ first: String, _ second: String) async {
        guard first != second else { return }
        recordUndo("Merge Voices")
        let (destination, source) = canonicalMerge(first, second)
        await attempt("Merge voices") { try await SpeakerStore.shared.merge(source, into: destination) }
        voicesSelection = [destination]
        await finishEdit(reloadDatabase: true)
    }

    private func summary(for voiceprint: Voiceprint) -> VoiceSummary {
        VoiceSummary(
            id: voiceprint.id,
            name: voiceprint.name,
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
