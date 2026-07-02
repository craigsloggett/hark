import Foundation

/// The labeling window's edits. Each records an undo snapshot, mutates the overlay and/or the
/// voiceprint database, then finishes through `apply`/`finishEdit` on the main type.
extension LabelingModel {
    /// Relabels a pre-populated speaker for this transcript only, leaving the voiceprint untouched.
    func renameOverride(token: String, to name: String) async {
        guard var detail else { return }
        recordUndo("Rename")
        detail.overlay[token, default: SessionSpeaker()].nameOverride = name.normalizedName
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
    /// enrolls a new voiceprint from the stored centroid when there is one, or, for a recording with no
    /// saved voice sample, falls back to a transcript-only label so the action is never a silent no-op.
    func nameSpeaker(token: String, to name: String) async {
        guard let name = name.normalizedName, var detail else { return }
        if let id = detail.overlay[token]?.voiceprintID {
            recordUndo("Name Voice")
            await attempt("Rename voice") { try await SpeakerStore.shared.rename(id: id, to: name) }
            detail.overlay[token]?.confirmed = true
            await apply(detail, reloadDatabase: true)
        } else if canEnroll(token: token) {
            await enrollAndBind(token: token, name: name, undoLabel: "Name Voice")
        } else {
            await renameOverride(token: token, to: name)
        }
    }

    /// Assigns this transcript's speaker to a saved voice. Label-only by design: it does not teach the
    /// voice this clip, so a wrong pick is a cheap, reversible correction rather than a polluting one
    /// (teaching is the deliberate `teachVoice`).
    func rebind(token: String, toVoiceprint id: String) async {
        guard var detail else { return }
        recordUndo("Assign Voice")
        detail.overlay[token, default: SessionSpeaker()].bind(to: id)
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
        await attempt("Teach voice") {
            try await SpeakerStore.shared.addSample(
                toVoiceprint: id, embedding: embedding, duration: detail.overlay[token]?.duration ?? 0
            )
        }
        detail.overlay[token]?.confirmed = true
        await apply(detail, reloadDatabase: true)
    }

    /// Enrolls a brand-new voiceprint for this speaker (optionally named) and binds to it.
    func addNewVoice(token: String, name: String?) async {
        await enrollAndBind(token: token, name: name, undoLabel: "Add Voice")
    }

    /// Enrolls a new voiceprint for this speaker, unless it would duplicate a voice Hark already knows,
    /// in which case it defers to a confirmation (`pendingEnrollment`) instead of forking the identity.
    private func enrollAndBind(token: String, name: String?, undoLabel: String) async {
        guard detail?.overlay[token]?.embedding != nil else { return }
        if let duplicate = await probableDuplicate(token: token, name: name) {
            pendingEnrollment = PendingEnrollment(
                token: token, name: name, undoLabel: undoLabel,
                match: duplicate.match, reason: duplicate.reason
            )
            return
        }
        await performEnroll(token: token, name: name, undoLabel: undoLabel)
    }

    private func performEnroll(token: String, name: String?, undoLabel: String) async {
        guard var detail, let embedding = detail.overlay[token]?.embedding else { return }
        recordUndo(undoLabel)
        let duration = detail.overlay[token]?.duration ?? 0
        let enrolled = await attempt("Enroll voice") {
            try await SpeakerStore.shared.enroll(embedding: embedding, duration: duration, name: name)
        }
        guard let voiceprint = enrolled else {
            discardLastUndoStep()
            return
        }
        detail.overlay[token, default: SessionSpeaker()].bind(to: voiceprint.id)
        await apply(detail, reloadDatabase: true)
    }

    /// The saved voice a new enroll would likely duplicate: one already using the typed name, or one
    /// within the confident-match distance of this speaker's voice. `nil` when the enroll looks distinct.
    func probableDuplicate(
        token: String, name: String?
    ) async -> (match: Voiceprint, reason: PendingEnrollment.Reason)? {
        if let name = name?.normalizedName, let sameName = namedVoice(matching: name) {
            return (sameName, .sameName)
        }
        guard let embedding = detail?.overlay[token]?.embedding,
              let near = try? await SpeakerStore.shared.nearestNamed(to: embedding),
              near.distance <= Float(Preferences.speakerConfidentMatchThreshold)
        else { return nil }
        return (near.voiceprint, .nearDuplicate(near.distance))
    }

    /// A non-tombstoned saved voice whose name equals `name`, case-insensitively.
    private func namedVoice(matching name: String) -> Voiceprint? {
        voiceprintsByID.values.first { voiceprint in
            voiceprint.redirectID == nil && voiceprint.name?.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Confirms the pending enroll as a genuinely separate, new voice.
    func createPendingAsNewVoice() async {
        guard let pending = pendingEnrollment else { return }
        pendingEnrollment = nil
        await performEnroll(token: pending.token, name: pending.name, undoLabel: pending.undoLabel)
    }

    /// Resolves the pending enroll by binding this speaker to the existing voice and teaching it this clip.
    func addPendingToExistingVoice() async {
        guard let pending = pendingEnrollment else { return }
        pendingEnrollment = nil
        await useExistingVoice(token: pending.token, id: pending.match.id)
    }

    /// Binds a speaker to a known voice and teaches it this clip, the "yes, it's them" answer to a
    /// duplicate warning. The deliberate affirmation makes teaching warranted here, unlike a casual `rebind`.
    private func useExistingVoice(token: String, id: String) async {
        guard var detail else { return }
        recordUndo("Use Saved Voice")
        if let embedding = detail.overlay[token]?.embedding {
            await attempt("Teach voice") {
                try await SpeakerStore.shared.addSample(
                    toVoiceprint: id, embedding: embedding, duration: detail.overlay[token]?.duration ?? 0
                )
            }
        }
        detail.overlay[token, default: SessionSpeaker()].bind(to: id)
        await apply(detail, reloadDatabase: true)
    }

    /// Renames a saved voice everywhere it is used, a global identity edit unlike a transcript relabel.
    func renameVoice(id: String, to name: String) async {
        guard let name = name.normalizedName else { return }
        recordUndo("Rename Voice")
        await attempt("Rename voice") { try await SpeakerStore.shared.rename(id: id, to: name) }
        await finishEdit(reloadDatabase: true)
    }

    /// Forgets a saved voice. Speakers bound to it in the loaded transcript fall back to positional;
    /// other recordings do the same the next time they are opened. Works from the global manager too,
    /// where no transcript is loaded.
    func forgetVoice(id: String) async {
        recordUndo("Forget Voice")
        await attempt("Forget voice") { try await SpeakerStore.shared.remove(id: id) }
        peopleSelection = []
        voicesSelection.remove(id)
        guard var detail else {
            await finishEdit(reloadDatabase: true)
            return
        }
        for (token, speaker) in detail.overlay where speaker.voiceprintID == id {
            detail.overlay[token]?.voiceprintID = nil
        }
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
            guard let embedding = detail.overlay[token]?.embedding else { continue }
            let enrolled = await attempt("Enroll voice") {
                try await SpeakerStore.shared.enroll(
                    embedding: embedding, duration: detail.overlay[token]?.duration ?? 0, name: nil
                )
            }
            guard let voiceprint = enrolled else { continue }
            detail.overlay[token]?.voiceprintID = voiceprint.id
            ids.append(voiceprint.id)
        }
        await refreshVoiceprints()
        guard ids.count == 2, ids[0] != ids[1] else {
            await apply(detail, reloadDatabase: true)
            return
        }

        let (destination, source) = canonicalMerge(ids[0], ids[1])
        await attempt("Merge voices") { try await SpeakerStore.shared.merge(source, into: destination) }
        for token in tokens {
            detail.overlay[token]?.voiceprintID = destination
            detail.overlay[token]?.matchDistance = nil
            detail.overlay[token]?.confirmed = true
        }
        peopleSelection = []
        await apply(detail, reloadDatabase: true)
    }

    /// Chooses which voiceprint survives a merge: the named one, else the one with more samples.
    func canonicalMerge(_ first: String, _ second: String) -> (destination: String, source: String) {
        let firstPrint = voiceprintsByID[first]
        let secondPrint = voiceprintsByID[second]
        if firstPrint?.name != nil, secondPrint?.name == nil { return (first, second) }
        if secondPrint?.name != nil, firstPrint?.name == nil { return (second, first) }
        if (firstPrint?.samples.count ?? 0) >= (secondPrint?.samples.count ?? 0) { return (first, second) }
        return (second, first)
    }
}
