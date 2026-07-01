import Foundation

/// The labeling window's edits. Each records an undo snapshot, mutates the overlay and/or the
/// voiceprint database, then finishes through `apply`/`finishEdit` on the main type.
extension LabelingModel {
    /// Relabels a pre-populated speaker for this transcript only, leaving the voiceprint untouched.
    func renameOverride(token: String, to name: String) async {
        guard var detail else { return }
        recordUndo("Rename")
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.nameOverride = trimmed.isEmpty ? nil : trimmed
        detail.overlay[token] = speaker
        await apply(detail, reloadDatabase: false)
    }

    /// Drops a transcript-only label, returning the chip to its positional "Speaker N".
    func clearLabel(token: String) async {
        guard var detail, detail.overlay[token]?.nameOverride != nil else { return }
        recordUndo("Clear Label")
        detail.overlay[token]?.nameOverride = nil
        await apply(detail, reloadDatabase: false)
    }

    /// Clears a saved-voice binding for this transcript, leaving the underlying voice untouched. The
    /// escape hatch for an assignment made by mistake, and the "reject" of a tentative match; any
    /// transcript label is kept.
    func unassign(token: String) async {
        guard var detail, detail.overlay[token]?.voiceprintID != nil else { return }
        recordUndo("Unassign")
        detail.overlay[token]?.voiceprintID = nil
        detail.overlay[token]?.matchDistance = nil
        detail.overlay[token]?.confirmed = false
        await apply(detail, reloadDatabase: false)
    }

    /// Confirms a tentative auto-match so it reads plainly, without teaching the voice this clip.
    func confirmMatch(token: String) async {
        guard var detail, detail.overlay[token]?.voiceprintID != nil else { return }
        recordUndo("Confirm")
        detail.overlay[token]?.confirmed = true
        await apply(detail, reloadDatabase: false)
    }

    /// Names an unlabeled speaker: renames the bound voiceprint if one exists (enrollment identity),
    /// otherwise enrolls a new voiceprint from the stored centroid.
    func nameSpeaker(token: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var detail else { return }
        if let id = detail.overlay[token]?.voiceprintID {
            recordUndo("Name Voice")
            try? await SpeakerStore.shared.rename(id: id, to: trimmed)
            detail.overlay[token]?.confirmed = true
            await apply(detail, reloadDatabase: true)
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
        speaker.matchDistance = nil
        speaker.confirmed = true
        detail.overlay[token] = speaker
        await apply(detail, reloadDatabase: false)
    }

    /// Teaches the bound saved voice this clip, improving future recognition. A deliberate act, so a
    /// casual assignment never shifts a voice's centroid on its own; teaching also confirms the match.
    func teachVoice(token: String) async {
        guard var detail,
              let id = detail.overlay[token]?.voiceprintID,
              let embedding = detail.overlay[token]?.embedding
        else { return }
        recordUndo("Teach Voice")
        try? await SpeakerStore.shared.addSample(
            toVoiceprint: id, embedding: embedding, duration: detail.overlay[token]?.duration ?? 0
        )
        detail.overlay[token]?.confirmed = true
        await apply(detail, reloadDatabase: true)
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
            discardLastUndoStep()
            return
        }
        var speaker = detail.overlay[token] ?? SessionSpeaker()
        speaker.voiceprintID = voiceprint.id
        speaker.nameOverride = nil
        speaker.matchDistance = nil
        speaker.confirmed = true
        detail.overlay[token] = speaker
        await apply(detail, reloadDatabase: true)
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
        peopleSelection = []
        await apply(detail, reloadDatabase: true)
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
            await apply(detail, reloadDatabase: true)
            return
        }

        let (destination, source) = canonicalMerge(ids[0], ids[1])
        _ = try? await SpeakerStore.shared.merge(source, into: destination)
        for token in tokens {
            detail.overlay[token]?.voiceprintID = destination
            detail.overlay[token]?.matchDistance = nil
            detail.overlay[token]?.confirmed = true
        }
        peopleSelection = []
        await apply(detail, reloadDatabase: true)
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
}
