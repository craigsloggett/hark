import Foundation
import OSLog
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
    private let logger = Logger(category: "LabelingModel")
    var sidebarSelection: SidebarItem?
    var peopleSelection: Set<String> = []
    /// The voices selected in the global manager (by voiceprint id), for merging across recordings.
    var voicesSelection: Set<String> = []
    private(set) var detail: SessionDetail?
    private(set) var voiceprintsByID: [String: Voiceprint] = [:]
    /// Surviving voiceprint id to the number of recordings it appears in, for the People inspector.
    private(set) var voiceUsage: [String: Int] = [:]
    /// A duplicate a deliberate enroll would create: set instead of enrolling, so the UI can offer to
    /// reuse the existing voice. `nil` when no enroll is awaiting that choice.
    var pendingEnrollment: PendingEnrollment?

    var selection: URL? {
        if case let .session(url) = sidebarSelection { return url }
        return nil
    }

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
        await attempt("Undo restore") { try await SpeakerStore.shared.replaceAll(snapshot.voiceprints) }
        if var detail {
            detail.overlay = snapshot.overlay
            self.detail = detail
        }
        peopleSelection = snapshot.peopleSelection
        await finishEdit(reloadDatabase: true)
    }

    // MARK: Loading

    func refreshVoiceprints() async {
        let all = await attempt("Load voiceprints") { try await SpeakerStore.shared.voiceprints() } ?? []
        voiceprintsByID = all.byID
    }

    func loadSelected() async {
        peopleSelection = []
        voicesSelection = []
        pendingEnrollment = nil
        undoStack = []
        if let selection {
            detail = await attempt("Load recording") { try library.loadDetail(selection) }
        } else {
            detail = nil
        }
        refreshUsage()
    }

    private func refreshUsage() {
        voiceUsage = library.voiceUsage(resolving: voiceprintsByID)
    }

    var currentSummary: SessionSummary? {
        library.sessions.first { $0.url == selection }
    }

    var currentTitle: String {
        currentSummary?.title ?? "Recording"
    }

    /// The recording date, shown under the titlebar name only when a custom name displaces it.
    var currentSubtitle: String {
        guard let summary = currentSummary, summary.name != nil else { return "" }
        return summary.dateLabel
    }

    // MARK: Display

    /// Display resolution over the loaded overlay (empty when none) and the voiceprint snapshot.
    var resolver: SpeakerResolver {
        SpeakerResolver(overlay: detail?.overlay ?? [:], voiceprints: voiceprintsByID)
    }

    func positionalLabel(token: String) -> String {
        Speaker(token: token)?.label ?? token
    }

    func color(for token: String) -> Color {
        .speaker(for: resolver.identityKey(for: token))
    }

    var turnGroups: [TurnGroup] {
        guard let detail else { return [] }
        let resolver = resolver
        var groups: [TurnGroup] = []
        for segment in detail.segments {
            let token = segment.speaker.token
            let key = resolver.identityKey(for: token)
            if let last = groups.indices.last, resolver.identityKey(for: groups[last].token) == key {
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

    /// The speaker's total speech in this transcript ("2m 14s"), or `nil` under a second of it.
    func speakingTime(token: String) -> String? {
        guard let seconds = speakingSeconds(token: token) else { return nil }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)
        )
    }

    /// The summed segment durations behind `speakingTime`; `nil` under one second, which reads as
    /// noise rather than a stat worth a subtitle slot.
    func speakingSeconds(token: String) -> Double? {
        guard let detail else { return nil }
        let seconds = detail.segments
            .filter { $0.speaker.token == token }
            .reduce(0.0) { $0 + max(0, $1.end - $1.start) }
        return seconds >= 1 ? seconds : nil
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
            .filter { !$0.isTombstone && $0.name != nil && $0.id != bound }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    func canEnroll(token: String) -> Bool {
        detail?.overlay[token]?.embedding != nil
    }

    var canMerge: Bool {
        peopleSelection.count == 2 && !peopleSelection.contains(Speaker.you.token)
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
    }

    /// Writes the overlay and re-renders `transcript.txt` with the current voiceprint names.
    private func persist() async {
        guard let detail else { return }
        await attempt("Save speaker overlay") { try Session(url: detail.url).writeSpeakers(detail.overlay) }
        // `finishEdit` refreshes the snapshot before persisting whenever the database changed.
        await attempt("Re-render transcript") {
            try TranscriptionService.rerenderTranscript(at: detail.url, voiceprints: Array(voiceprintsByID.values))
        }
    }

    /// Runs a store or disk write, logging a failure rather than surfacing it, so an edit degrades
    /// visibly in Console instead of silently diverging from disk. Internal so the editing methods in
    /// the sibling files report through the same channel.
    @discardableResult
    func attempt<T>(_ label: String, _ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            logger.error("\(label, privacy: .public) failed: \(error, privacy: .public)")
            return nil
        }
    }
}

#if DEBUG
    extension LabelingModel {
        /// A model wired to a fixed transcript and voice set, for SwiftUI previews and tests
        /// without touching disk or `SpeakerStore`.
        static func preview(detail: SessionDetail, voiceprints: [Voiceprint] = []) -> LabelingModel {
            let model = LabelingModel()
            model.detail = detail
            model.voiceprintsByID = voiceprints.byID
            return model
        }
    }
#endif
