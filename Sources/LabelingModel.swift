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
/// `SpeakerStore`, updates the overlay, re-renders `transcript.txt`, and refreshes the snapshot.
@MainActor
@Observable
final class LabelingModel {
    let library = SessionLibrary()
    var selection: URL?
    var peopleSelection: Set<String> = []
    private(set) var detail: SessionDetail?
    private(set) var voiceprintsByID: [String: Voiceprint] = [:]

    // MARK: Loading

    func refreshVoiceprints() async {
        let all = await (try? SpeakerStore.shared.voiceprints()) ?? []
        voiceprintsByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func loadSelected() async {
        peopleSelection = []
        guard let selection else {
            detail = nil
            return
        }
        detail = try? library.loadDetail(selection)
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

    // MARK: Editing

    /// Relabels a pre-populated speaker for this transcript only, leaving the voiceprint untouched.
    func renameOverride(token: String, to name: String) async {
        guard var detail else { return }
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.nameOverride = trimmed.isEmpty ? nil : trimmed
        detail.overlay[token] = speaker
        self.detail = detail
        await persist()
    }

    /// Names an unlabeled speaker: renames the bound voiceprint if one exists (enrollment identity),
    /// otherwise enrolls a new voiceprint from the stored centroid.
    func nameSpeaker(token: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detail else { return }
        if let id = detail.overlay[token]?.voiceprintID {
            try? await SpeakerStore.shared.rename(id: id, to: trimmed)
            await refreshVoiceprints()
            await persist()
        } else {
            await enrollAndBind(token: token, name: trimmed)
        }
    }

    /// Binds this speaker to an existing voiceprint (a matching correction) and teaches it this voice.
    func rebind(token: String, toVoiceprint id: String) async {
        guard var detail else { return }
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        if let embedding = speaker.embedding {
            try? await SpeakerStore.shared.addSample(
                toVoiceprint: id, embedding: embedding, duration: speaker.duration ?? 0
            )
        }
        speaker.voiceprintID = id
        speaker.nameOverride = nil
        detail.overlay[token] = speaker
        self.detail = detail
        await refreshVoiceprints()
        await persist()
    }

    /// Enrolls a brand-new voiceprint for this speaker (optionally named) and binds to it.
    func addNewVoice(token: String, name: String?) async {
        await enrollAndBind(token: token, name: name)
    }

    private func enrollAndBind(token: String, name: String?) async {
        guard var detail, let embedding = detail.overlay[token]?.embedding else { return }
        let duration = detail.overlay[token]?.duration ?? 0
        guard let voiceprint = try? await SpeakerStore.shared.enroll(
            embedding: embedding, duration: duration, name: name
        ) else { return }
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        speaker.voiceprintID = voiceprint.id
        speaker.nameOverride = nil
        detail.overlay[token] = speaker
        self.detail = detail
        await refreshVoiceprints()
        await persist()
    }

    /// Merges the two selected speakers into one identity (fixes an over-split voice). Positional-only
    /// speakers enroll first; the survivor keeps its name and gains the other's samples.
    func mergeSelected() async {
        guard canMerge, var detail else { return }
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
            return
        }

        let (destination, source) = canonicalMerge(ids[0], ids[1])
        _ = try? await SpeakerStore.shared.merge(source, into: destination)
        for token in tokens {
            detail.overlay[token]?.voiceprintID = destination
        }
        self.detail = detail
        peopleSelection = []
        await refreshVoiceprints()
        await persist()
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

    /// Writes the overlay and re-renders `transcript.txt` with the current voiceprint names.
    private func persist() async {
        guard let detail else { return }
        try? Session(url: detail.url).writeSpeakers(detail.overlay)
        let all = await (try? SpeakerStore.shared.voiceprints()) ?? []
        try? TranscriptionService.rerenderTranscript(at: detail.url, voiceprints: all)
    }
}
