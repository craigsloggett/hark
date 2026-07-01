import SwiftUI

/// Names saved voices from two surfaces: the speakers of the most recent recording (named in
/// context, then reflected in that session's transcript), and the full list of saved voiceprints.
struct VoicesSettingsView: View {
    @Environment(AudioRecorder.self) private var recorder

    @State private var voiceprints: [Voiceprint] = []
    @State private var recent: RecentSession?

    var body: some View {
        Form {
            if let recent {
                Section {
                    ForEach(recent.speakers) { speaker in
                        RecentSpeakerRow(label: speaker.label, initialName: speaker.name) { name in
                            await nameRecentSpeaker(speaker, to: name)
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
                        VoiceRow(
                            voiceprint: voiceprint,
                            onRename: { await rename(voiceprint, to: $0) },
                            onDelete: { await delete(voiceprint) }
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
        .task { await reload() }
    }

    // MARK: State

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
                return RecentSpeaker(token: token, voiceprintID: identity.id, label: label, name: identity.name ?? "")
            }
            // Numeric-aware so "Speaker 2" sorts before "Speaker 10".
            .sorted { $0.token.localizedStandardCompare($1.token) == .orderedAscending }
        return speakers.isEmpty ? nil : RecentSession(url: url, speakers: speakers)
    }

    // MARK: Actions

    private func rename(_ voiceprint: Voiceprint, to name: String) async {
        try? await SpeakerStore.shared.rename(id: voiceprint.id, to: name)
        await reload()
    }

    private func delete(_ voiceprint: Voiceprint) async {
        try? await SpeakerStore.shared.remove(id: voiceprint.id)
        await reload()
    }

    /// Persists the name to the shared database (for future sessions), then updates this session's
    /// overlay and re-renders its transcript so the change shows right away.
    private func nameRecentSpeaker(_ speaker: RecentSpeaker, to name: String) async {
        guard let sessionURL = recent?.url else { return }
        try? await SpeakerStore.shared.rename(id: speaker.voiceprintID, to: name)

        let session = Session(url: sessionURL)
        if var overlay = try? session.loadSpeakers() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            overlay[speaker.token] = SpeakerIdentity(id: speaker.voiceprintID, name: trimmed.isEmpty ? nil : trimmed)
            try? session.writeSpeakers(overlay)
            try? TranscriptionService.rerenderTranscript(at: sessionURL)
        }
        await reload()
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
    let name: String

    var id: String {
        token
    }
}

/// One speaker in the "last recording" section: a fixed label and an editable name.
private struct RecentSpeakerRow: View {
    let label: String
    let initialName: String
    let onCommit: (String) async -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(label: String, initialName: String, onCommit: @escaping (String) async -> Void) {
        self.label = label
        self.initialName = initialName
        self.onCommit = onCommit
        _draft = State(initialValue: initialName)
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            TextField("Add a name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { commit() }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != initialName else { return }
        Task { await onCommit(trimmed) }
    }
}

/// One saved voice: an editable name, recognition metadata, and a forget button.
private struct VoiceRow: View {
    let voiceprint: Voiceprint
    let onRename: (String) async -> Void
    let onDelete: () async -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(voiceprint: Voiceprint, onRename: @escaping (String) async -> Void, onDelete: @escaping () async -> Void) {
        self.voiceprint = voiceprint
        self.onRename = onRename
        self.onDelete = onDelete
        _draft = State(initialValue: voiceprint.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Unnamed voice", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { commit() }
                Button(role: .destructive) {
                    Task { await onDelete() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Forget this voice")
            }
            Text(metadata)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private var metadata: String {
        var parts: [String] = []
        if let last = voiceprint.lastEnrolledAt {
            parts.append("Last heard \(last.formatted(date: .abbreviated, time: .omitted))")
        }
        parts.append(Self.duration(voiceprint.totalDuration))
        let count = voiceprint.samples.count
        parts.append("\(count) sample\(count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (voiceprint.name ?? "") else { return }
        Task { await onRename(trimmed) }
    }

    private static func duration(_ seconds: Float) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
