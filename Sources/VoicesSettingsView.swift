import SwiftUI

/// Names saved voices from two surfaces: the speakers of the most recent recording (named in
/// context, then reflected in that session's transcript), and the full list of saved voiceprints.
///
/// Names are shown read-only and edited on demand behind a pencil; edits are buffered as drafts and
/// committed together by Save. Deleting a voice is immediate.
struct VoicesSettingsView: View {
    @Environment(AudioRecorder.self) private var recorder

    @State private var voiceprints: [Voiceprint] = []
    @State private var recent: RecentSession?
    /// Pending names keyed by voiceprint id, absent until a row is edited.
    @State private var drafts: [String: String] = [:]
    /// The voiceprint id whose name field is currently open, if any.
    @State private var editing: String?

    var body: some View {
        Form {
            if let recent {
                Section {
                    ForEach(recent.speakers) { speaker in
                        LabeledContent(speaker.label) {
                            nameControl(for: speaker.voiceprintID, placeholder: "Add a name")
                        }
                    }
                } header: {
                    Text("Name speakers from your last recording")
                } footer: {
                    Text("Naming a speaker updates that recording's transcript and remembers the voice for next time.")
                }
            }

            Section("Saved voices") {
                if voiceprints.isEmpty {
                    Text("No saved voices yet. Hark remembers each voice as you record, then you can name them here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(voiceprints) { voiceprint in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                nameControl(for: voiceprint.id, placeholder: "Unnamed voice")
                                Spacer(minLength: 8)
                                Button(role: .destructive) {
                                    Task { await delete(voiceprint) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Forget this voice")
                            }
                            Text(metadata(for: voiceprint))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
        .task { await reload() }
    }

    /// A read-only name that swaps to an editable field while `editing` points at `id`.
    private func nameControl(for id: String, placeholder: String) -> some View {
        HStack(spacing: 8) {
            NameEditor(
                placeholder: placeholder,
                draft: draftBinding(id),
                isEditing: editing == id,
                onBeginEdit: { editing = id },
                onEndEdit: { if editing == id { editing = nil } }
            )
            if editing != id {
                Button { editing = id } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename")
            }
        }
    }

    // MARK: Drafts

    /// The pending name for `id`, falling back to its saved name so the field opens pre-filled.
    private func draftBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { drafts[id] ?? savedName(id) },
            set: { drafts[id] = $0 }
        )
    }

    private func savedName(_ id: String) -> String {
        voiceprints.first { $0.id == id }?.name ?? ""
    }

    /// Drafts that differ from the saved name once trimmed, keyed by voiceprint id.
    private var changes: [String: String] {
        drafts.filter { id, value in normalized(value) != normalized(savedName(id)) }
    }

    private var hasChanges: Bool {
        !changes.isEmpty
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Actions

    private func reload() async {
        voiceprints = await (try? SpeakerStore.shared.voiceprints()) ?? []
        recent = loadRecentSession()
    }

    /// The most recent session's remote speakers, or `nil` when there's no recording yet or it had
    /// no diarized speakers (a mic-only clip never writes `speakers.json`).
    private func loadRecentSession() -> RecentSession? {
        guard let url = recorder.lastSessionURL,
              let overlay = try? Session(url: url).loadSpeakers(), !overlay.isEmpty
        else { return nil }
        let speakers = overlay
            .compactMap { token, identity -> RecentSpeaker? in
                guard let label = Speaker(token: token)?.label else { return nil }
                return RecentSpeaker(token: token, voiceprintID: identity.id, label: label)
            }
            // Numeric-aware so "Speaker 2" sorts before "Speaker 10".
            .sorted { $0.token.localizedStandardCompare($1.token) == .orderedAscending }
        return speakers.isEmpty ? nil : RecentSession(url: url, speakers: speakers)
    }

    private func delete(_ voiceprint: Voiceprint) async {
        try? await SpeakerStore.shared.remove(id: voiceprint.id)
        drafts[voiceprint.id] = nil
        if editing == voiceprint.id { editing = nil }
        await reload()
    }

    /// Persists every changed name to the shared database, then refreshes the last recording's
    /// overlay and transcript for any of its speakers that changed.
    private func save() async {
        let changed = changes
        for (id, value) in changed {
            try? await SpeakerStore.shared.rename(id: id, to: value)
        }
        if let recent, recent.speakers.contains(where: { changed.keys.contains($0.voiceprintID) }) {
            let session = Session(url: recent.url)
            if var overlay = try? session.loadSpeakers() {
                for speaker in recent.speakers where changed.keys.contains(speaker.voiceprintID) {
                    let name = normalized(changed[speaker.voiceprintID] ?? "")
                    overlay[speaker.token] = SpeakerIdentity(id: speaker.voiceprintID, name: name.isEmpty ? nil : name)
                }
                try? session.writeSpeakers(overlay)
                try? TranscriptionService.rerenderTranscript(at: recent.url)
            }
        }
        drafts = [:]
        editing = nil
        await reload()
    }

    // MARK: Formatting

    private func metadata(for voiceprint: Voiceprint) -> String {
        var parts: [String] = []
        if let last = voiceprint.lastEnrolledAt {
            parts.append("Last heard \(last.formatted(date: .abbreviated, time: .omitted))")
        }
        parts.append(Self.duration(voiceprint.totalDuration))
        let count = voiceprint.samples.count
        parts.append("\(count) sample\(count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private static func duration(_ seconds: Float) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The most recent session and its nameable remote speakers.
private struct RecentSession {
    let url: URL
    let speakers: [RecentSpeaker]
}

private struct RecentSpeaker: Identifiable {
    let token: String
    let voiceprintID: String
    let label: String

    var id: String {
        token
    }
}

/// A name shown as text until asked to edit, then a focused field that commits on Return or blur.
private struct NameEditor: View {
    let placeholder: String
    @Binding var draft: String
    let isEditing: Bool
    let onBeginEdit: () -> Void
    let onEndEdit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit(onEndEdit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { onEndEdit() }
                }
        } else {
            Text(draft.isEmpty ? placeholder : draft)
                .foregroundStyle(draft.isEmpty ? .secondary : .primary)
                .onTapGesture(perform: onBeginEdit)
        }
    }
}
