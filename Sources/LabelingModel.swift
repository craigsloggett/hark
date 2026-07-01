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

/// The state hub for the labeling window: the session list, the loaded transcript and its editable
/// speaker overlay, and a snapshot of the voiceprint database. Every edit writes through
/// `SpeakerStore`, updates the overlay, re-renders `transcript.txt`, and refreshes the snapshot, and
/// pushes an undo snapshot first so any edit is reversible.
@MainActor
@Observable
final class LabelingModel {
    let library = SessionLibrary()
    var selection: URL?
    var peopleSelection: Set<String> = []
    private(set) var detail: SessionDetail?
    private(set) var voiceprintsByID: [String: Voiceprint] = [:]
    /// Surviving voiceprint id to the number of recordings it appears in, for the People inspector.
    private(set) var voiceUsage: [String: Int] = [:]

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

    private func recordUndo(_ label: String) {
        guard let detail else { return }
        undoStack.append(UndoSnapshot(
            label: label,
            overlay: detail.overlay,
            voiceprints: Array(voiceprintsByID.values),
            peopleSelection: peopleSelection
        ))
        if undoStack.count > Self.undoDepth {
            undoStack.removeFirst(undoStack.count - Self.undoDepth)
        }
    }

    func undo() async {
        guard var detail, let snapshot = undoStack.popLast() else { return }
        try? await SpeakerStore.shared.replaceAll(snapshot.voiceprints)
        detail.overlay = snapshot.overlay
        self.detail = detail
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
        undoStack = []
        guard let selection else {
            detail = nil
            return
        }
        detail = try? library.loadDetail(selection)
        refreshUsage()
    }

    private func refreshUsage() {
        voiceUsage = library.voiceUsage(resolving: voiceprintsByID)
    }

    var currentTitle: String {
        library.sessions.first { $0.url == selection }?.title ?? "Recording"
    }

    // MARK: Display

    /// The resolved key that groups turns and colors chips: the bound voiceprint, else the token.
    private func identityKey(_ token: String) -> String {
        detail?.overlay[token]?.voiceprintID ?? token
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
}

// MARK: - Editing

/// Every edit records an undo snapshot first, mutates the overlay and/or the voiceprint database,
/// then writes the overlay and re-renders `transcript.txt` through `finishEdit`.
extension LabelingModel {
    /// Relabels a pre-populated speaker for this transcript only, leaving the voiceprint untouched.
    func renameOverride(token: String, to name: String) async {
        guard var detail else { return }
        recordUndo("Rename")
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.nameOverride = trimmed.isEmpty ? nil : trimmed
        detail.overlay[token] = speaker
        self.detail = detail
        await finishEdit(reloadDatabase: false)
    }

    /// Drops a transcript-only label, returning the chip to its positional "Speaker N".
    func clearLabel(token: String) async {
        guard var detail, detail.overlay[token]?.nameOverride != nil else { return }
        recordUndo("Clear Label")
        detail.overlay[token]?.nameOverride = nil
        self.detail = detail
        await finishEdit(reloadDatabase: false)
    }

    /// Clears a saved-voice binding for this transcript, leaving the underlying voice untouched. The
    /// escape hatch for an assignment made by mistake; any transcript label is kept.
    func unassign(token: String) async {
        guard var detail, detail.overlay[token]?.voiceprintID != nil else { return }
        recordUndo("Unassign")
        detail.overlay[token]?.voiceprintID = nil
        self.detail = detail
        await finishEdit(reloadDatabase: false)
    }

    /// Names an unlabeled speaker: renames the bound voiceprint if one exists (enrollment identity),
    /// otherwise enrolls a new voiceprint from the stored centroid.
    func nameSpeaker(token: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detail else { return }
        if let id = detail.overlay[token]?.voiceprintID {
            recordUndo("Name Voice")
            try? await SpeakerStore.shared.rename(id: id, to: trimmed)
            await finishEdit(reloadDatabase: true)
        } else {
            await enrollAndBind(token: token, name: trimmed, undoLabel: "Name Voice")
        }
    }

    /// Assigns this transcript's speaker to a saved voice. Label-only by design: it does not teach the
    /// voice this clip, so a wrong pick is a cheap, reversible correction rather than a polluting one
    /// (teaching is the deliberate `teachVoice`).
    func rebind(token: String, toVoiceprint id: String) async {
        guard var detail else { return }
        recordUndo("Assign Voice")
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        speaker.voiceprintID = id
        speaker.nameOverride = nil
        detail.overlay[token] = speaker
        self.detail = detail
        await finishEdit(reloadDatabase: false)
    }

    /// Teaches the bound saved voice this clip, improving future recognition. A deliberate act, so a
    /// casual assignment never shifts a voice's centroid on its own.
    func teachVoice(token: String) async {
        guard let detail,
              let id = detail.overlay[token]?.voiceprintID,
              let embedding = detail.overlay[token]?.embedding
        else { return }
        recordUndo("Teach Voice")
        try? await SpeakerStore.shared.addSample(
            toVoiceprint: id, embedding: embedding, duration: detail.overlay[token]?.duration ?? 0
        )
        await finishEdit(reloadDatabase: true)
    }

    /// Enrolls a brand-new voiceprint for this speaker (optionally named) and binds to it.
    func addNewVoice(token: String, name: String?) async {
        await enrollAndBind(token: token, name: name, undoLabel: "Add Voice")
    }

    private func enrollAndBind(token: String, name: String?, undoLabel: String) async {
        guard var detail, let embedding = detail.overlay[token]?.embedding else { return }
        recordUndo(undoLabel)
        let duration = detail.overlay[token]?.duration ?? 0
        guard let voiceprint = try? await SpeakerStore.shared.enroll(
            embedding: embedding, duration: duration, name: name
        ) else {
            undoStack.removeLast()
            return
        }
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        speaker.voiceprintID = voiceprint.id
        speaker.nameOverride = nil
        detail.overlay[token] = speaker
        self.detail = detail
        await finishEdit(reloadDatabase: true)
    }

    /// Renames a saved voice everywhere it is used, a global identity edit unlike a transcript relabel.
    func renameVoice(id: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordUndo("Rename Voice")
        try? await SpeakerStore.shared.rename(id: id, to: trimmed)
        await finishEdit(reloadDatabase: true)
    }

    /// Forgets a saved voice. Speakers bound to it in this transcript fall back to positional; other
    /// recordings do the same the next time they are opened.
    func forgetVoice(id: String) async {
        guard var detail else { return }
        recordUndo("Forget Voice")
        try? await SpeakerStore.shared.remove(id: id)
        for (token, speaker) in detail.overlay where speaker.voiceprintID == id {
            detail.overlay[token]?.voiceprintID = nil
        }
        self.detail = detail
        peopleSelection = []
        await finishEdit(reloadDatabase: true)
    }

    /// Merges the two selected speakers into one identity (fixes an over-split voice). Positional-only
    /// speakers enroll first; the survivor keeps its name and gains the other's samples.
    func mergeSelected() async {
        guard canMerge, var detail else { return }
        recordUndo("Merge Voices")
        let tokens = Array(peopleSelection)
        var ids: [String] = []
        for token in tokens {
            if let id = detail.overlay[token]?.voiceprintID {
                ids.append(id)
                continue
            }
            guard let embedding = detail.overlay[token]?.embedding,
                  let voiceprint = try? await SpeakerStore.shared.enroll(
                      embedding: embedding, duration: detail.overlay[token]?.duration ?? 0, name: nil
                  )
            else { continue }
            detail.overlay[token]?.voiceprintID = voiceprint.id
            ids.append(voiceprint.id)
        }
        await refreshVoiceprints()
        guard ids.count == 2, ids[0] != ids[1] else {
            self.detail = detail
            await finishEdit(reloadDatabase: true)
            return
        }

        let (destination, source) = canonicalMerge(ids[0], ids[1])
        _ = try? await SpeakerStore.shared.merge(source, into: destination)
        for token in tokens {
            detail.overlay[token]?.voiceprintID = destination
        }
        self.detail = detail
        peopleSelection = []
        await finishEdit(reloadDatabase: true)
    }

    /// Chooses which voiceprint survives a merge: the named one, else the one with more samples.
    private func canonicalMerge(_ first: String, _ second: String) -> (destination: String, source: String) {
        let firstPrint = voiceprintsByID[first]
        let secondPrint = voiceprintsByID[second]
        if firstPrint?.name != nil, secondPrint?.name == nil { return (first, second) }
        if secondPrint?.name != nil, firstPrint?.name == nil { return (second, first) }
        if (firstPrint?.samples.count ?? 0) >= (secondPrint?.samples.count ?? 0) { return (first, second) }
        return (second, first)
    }

    /// Refreshes the voiceprint snapshot (when the database changed), writes the overlay, re-renders
    /// `transcript.txt`, and recomputes cross-session usage.
    private func finishEdit(reloadDatabase: Bool) async {
        if reloadDatabase {
            await refreshVoiceprints()
        }
        await persist()
        refreshUsage()
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
            usage: [String: Int] = [:]
        ) -> LabelingModel {
            let model = LabelingModel()
            model.detail = detail
            model.voiceprintsByID = Dictionary(
                voiceprints.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            model.voiceUsage = usage
            return model
        }
    }
#endif
