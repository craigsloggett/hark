import Foundation
import SwiftUI

/// A run of consecutive turns from one resolved identity, the unit the chat renders as a bubble group.
/// Two different tokens that resolve to the same voiceprint (after a merge) collapse into one group.
struct TurnGroup: Identifiable {
    let id: Int
    let token: String
    let speaker: Speaker
    var segments: [TranscriptSegment]
}

/// The recordings sidebar's selection: the global voices manager or one recording.
enum SidebarItem: Hashable {
    case voices
    case session(URL)
}

/// The state hub for the labeling window: the session list, the loaded transcript and its editable
/// speaker overlay, and a snapshot of the voiceprint database. Every edit (in `LabelingModel+Editing`)
/// pushes an undo snapshot, mutates the overlay and/or `SpeakerStore`, then re-renders `transcript.txt`.
@MainActor
@Observable
final class LabelingModel {
    let library = SessionLibrary()
    /// The sidebar's selection: the global voices view or one recording.
    var sidebarSelection: SidebarItem?
    var peopleSelection: Set<String> = []
    /// The voices selected in the global manager (by voiceprint id), for merging across recordings.
    var voicesSelection: Set<String> = []
    private(set) var detail: SessionDetail?
    private(set) var voiceprintsByID: [String: Voiceprint] = [:]
    /// Surviving voiceprint id to the number of recordings it appears in, for the People inspector.
    private(set) var voiceUsage: [String: Int] = [:]
    /// Near-identical saved voices offered for merging in the global manager.
    private(set) var duplicateSuggestions: [DuplicateSuggestion] = []
    /// A duplicate a deliberate enroll would create: set instead of enrolling, so the UI can offer to
    /// reuse the existing voice. `nil` when no enroll is awaiting that choice.
    var pendingEnrollment: PendingEnrollment?

    /// The loaded recording, derived from the sidebar selection (`nil` in the voices view).
    var selection: URL? {
        if case let .session(url) = sidebarSelection { return url }
        return nil
    }

    /// Whether the sidebar is showing the global voices manager rather than a recording.
    var showsVoices: Bool {
        sidebarSelection == .voices
    }

    // MARK: Undo

    /// A pre-edit snapshot of everything an action can touch. Undo restores it wholesale, which keeps
    /// every action reversible through one mechanism; the database is small enough to copy per step.
    private struct UndoSnapshot {
        let label: String
        let overlay: [String: SessionSpeaker]
        let voiceprints: [Voiceprint]
        let peopleSelection: Set<String>
    }

    private var undoStack: [UndoSnapshot] = []
    private static let undoDepth = 25

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var undoActionLabel: String? {
        undoStack.last.map { "Undo \($0.label)" }
    }

    /// Snapshots the current state under `label` before an edit. Internal so the editing methods in the
    /// sibling files record their own step. Works without a loaded session so global voice edits (which
    /// touch only the database) are undoable too.
    func recordUndo(_ label: String) {
        undoStack.append(UndoSnapshot(
            label: label,
            overlay: detail?.overlay ?? [:],
            voiceprints: Array(voiceprintsByID.values),
            peopleSelection: peopleSelection
        ))
        if undoStack.count > Self.undoDepth {
            undoStack.removeFirst(undoStack.count - Self.undoDepth)
        }
    }

    /// Drops the most recent undo snapshot, for an edit that recorded one then aborted.
    func discardLastUndoStep() {
        if !undoStack.isEmpty {
            undoStack.removeLast()
        }
    }

    func undo() async {
        guard let snapshot = undoStack.popLast() else { return }
        try? await SpeakerStore.shared.replaceAll(snapshot.voiceprints)
        if var detail {
            detail.overlay = snapshot.overlay
            self.detail = detail
        }
        peopleSelection = snapshot.peopleSelection
        await finishEdit(reloadDatabase: true)
    }

    // MARK: Loading

    func refreshVoiceprints() async {
        let all = await (try? SpeakerStore.shared.voiceprints()) ?? []
        voiceprintsByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func loadSelected() async {
        peopleSelection = []
        voicesSelection = []
        pendingEnrollment = nil
        undoStack = []
        detail = selection.flatMap { try? library.loadDetail($0) }
        refreshUsage()
        await refreshDuplicateSuggestions()
    }

    private func refreshUsage() {
        voiceUsage = library.voiceUsage(resolving: voiceprintsByID)
    }

    /// Recomputes the global manager's near-identical voice pairs, keeping only those with at least one
    /// named side (so there is a name to merge toward), the named side as the target. Here rather than
    /// in the sibling file because it sets the `private(set)` list.
    func refreshDuplicateSuggestions() async {
        let threshold = Float(Preferences.speakerConfidentMatchThreshold)
        let pairs = await (try? SpeakerStore.shared.duplicatePairs(within: threshold)) ?? []
        duplicateSuggestions = pairs.compactMap { pair in
            guard pair.first.name != nil || pair.second.name != nil else { return nil }
            let first = summary(for: pair.first)
            let second = summary(for: pair.second)
            let (primary, secondary) = first.isNamed || !second.isNamed ? (first, second) : (second, first)
            return DuplicateSuggestion(primary: primary, secondary: secondary, distance: pair.distance)
        }
    }

    var currentTitle: String {
        library.sessions.first { $0.url == selection }?.title ?? "Recording"
    }

    // MARK: Display

    /// The resolved key that groups turns and colors chips: the bound voiceprint (following merge
    /// redirects, so tokens merged elsewhere still collapse), else the token.
    private func identityKey(_ token: String) -> String {
        guard let id = detail?.overlay[token]?.voiceprintID else { return token }
        return Voiceprint.survivor(of: id, in: voiceprintsByID)?.id ?? id
    }

    func displayName(token: String) -> String? {
        guard let detail else { return nil }
        return SpeakerDisplay.name(token: token, overlay: detail.overlay, voiceprints: voiceprintsByID)
    }

    /// The chip's editing state, driving both its look and the popover's actions.
    func binding(token: String) -> SpeakerBinding {
        guard let detail else { return .unknown }
        return SpeakerDisplay.binding(token: token, overlay: detail.overlay, voiceprints: voiceprintsByID)
    }

    /// Whether the token is a borderline auto-match worth confirming, shown as "Likely <name>".
    func isLikelyMatch(token: String) -> Bool {
        guard let detail else { return false }
        return SpeakerDisplay.isLikelyMatch(
            token: token,
            overlay: detail.overlay,
            voiceprints: voiceprintsByID,
            likelyAbove: Float(Preferences.speakerConfidentMatchThreshold)
        )
    }

    func positionalLabel(token: String) -> String {
        Speaker(token: token)?.label ?? token
    }

    func color(for token: String) -> Color {
        .speaker(for: identityKey(token))
    }

    var turnGroups: [TurnGroup] {
        guard let detail else { return [] }
        var groups: [TurnGroup] = []
        for segment in detail.segments {
            let token = segment.speaker.token
            if let last = groups.indices.last, identityKey(groups[last].token) == identityKey(token) {
                groups[last].segments.append(segment)
            } else {
                groups.append(TurnGroup(id: groups.count, token: token, speaker: segment.speaker, segments: [segment]))
            }
        }
        return groups
    }

    // MARK: People roster

    /// The speakers in this transcript, in first-appearance order (includes "You").
    var rosterTokens: [String] {
        guard let detail else { return [] }
        var seen: Set<String> = []
        return detail.segments.compactMap { segment in
            seen.insert(segment.speaker.token).inserted ? segment.speaker.token : nil
        }
    }

    func turnCount(token: String) -> Int {
        detail?.segments.count(where: { $0.speaker.token == token }) ?? 0
    }

    func sampleCount(token: String) -> Int {
        guard let id = detail?.overlay[token]?.voiceprintID,
              let voiceprint = Voiceprint.survivor(of: id, in: voiceprintsByID)
        else { return detail?.overlay[token]?.embedding == nil ? 0 : 1 }
        return voiceprint.samples.count
    }

    /// How many recordings a token's bound voice appears in beyond this one, for the roster subtitle.
    func otherRecordings(token: String) -> Int {
        guard let id = detail?.overlay[token]?.voiceprintID,
              let survivor = Voiceprint.survivor(of: id, in: voiceprintsByID)
        else { return 0 }
        return max(0, (voiceUsage[survivor.id] ?? 0) - 1)
    }

    /// Named, non-tombstoned voiceprints the user can assign to a speaker, minus its current binding.
    func assignableVoiceprints(excluding token: String) -> [Voiceprint] {
        let bound = detail?.overlay[token]?.voiceprintID
        return voiceprintsByID.values
            .filter { $0.redirectID == nil && $0.name != nil && $0.id != bound }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    func canEnroll(token: String) -> Bool {
        detail?.overlay[token]?.embedding != nil
    }

    var canMerge: Bool {
        peopleSelection.count == 2 && !peopleSelection.contains("you")
    }

    // MARK: Edit plumbing

    /// Applies an edited overlay and finishes the edit. The editing methods in the sibling file route
    /// their `detail` writes through here, so `detail`'s setter stays private to this file.
    func apply(_ detail: SessionDetail, reloadDatabase: Bool) async {
        self.detail = detail
        await finishEdit(reloadDatabase: reloadDatabase)
    }

    /// Refreshes the voiceprint snapshot (when the database changed), writes the overlay, re-renders
    /// `transcript.txt`, and recomputes cross-session usage.
    func finishEdit(reloadDatabase: Bool) async {
        if reloadDatabase {
            await refreshVoiceprints()
        }
        await persist()
        refreshUsage()
        if reloadDatabase {
            await refreshDuplicateSuggestions()
        }
    }

    /// Writes the overlay and re-renders `transcript.txt` with the current voiceprint names.
    private func persist() async {
        guard let detail else { return }
        try? Session(url: detail.url).writeSpeakers(detail.overlay)
        let all = await (try? SpeakerStore.shared.voiceprints()) ?? []
        try? TranscriptionService.rerenderTranscript(at: detail.url, voiceprints: all)
    }
}

#if DEBUG
    extension LabelingModel {
        /// A model wired to a fixed transcript and voice set, for SwiftUI previews and screenshot
        /// rendering without touching disk or `SpeakerStore`.
        static func preview(
            detail: SessionDetail,
            voiceprints: [Voiceprint] = [],
            usage: [String: Int] = [:],
            suggestions: [DuplicateSuggestion] = []
        ) -> LabelingModel {
            let model = LabelingModel()
            model.detail = detail
            model.voiceprintsByID = Dictionary(
                voiceprints.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            model.voiceUsage = usage
            model.duplicateSuggestions = suggestions
            return model
        }
    }
#endif
