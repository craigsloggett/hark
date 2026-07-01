import SwiftUI

/// Every saved voice across all recordings, with cross-session rename, forget, and merge, plus a
/// "possible duplicates" band that surfaces near-identical voices to consolidate. Reached from the
/// recordings sidebar; its edits share the window's undo.
struct VoicesManagerView: View {
    @Bindable var model: LabelingModel
    @State private var renamingID: String?
    @State private var renameDraft = ""
    @State private var forgettingID: String?
    @State private var confirmingMerge = false

    var body: some View {
        Group {
            if model.voices.isEmpty {
                ContentUnavailableView(
                    "No saved voices yet",
                    systemImage: "person.2.wave.2",
                    description: Text("Name a speaker in a transcript and Hark saves their voice here.")
                )
            } else {
                content
            }
        }
        .navigationTitle("Voices")
        .navigationSubtitle(subtitle)
        .renameVoiceAlert(id: $renamingID, draft: $renameDraft) { id, name in
            await model.renameVoice(id: id, to: name)
        }
        .forgetVoiceDialog(id: $forgettingID) { await model.forgetVoice(id: $0) }
        .mergeVoicesDialog(isPresented: $confirmingMerge) { await model.mergeSelectedVoices() }
    }

    private var subtitle: String {
        String(count: model.voices.count, "saved voice")
    }

    private var content: some View {
        VStack(spacing: 0) {
            if !model.duplicateSuggestions.isEmpty {
                suggestions
                Divider()
            }
            List(model.voices, selection: $model.voicesSelection) { voice in
                VoiceRow(voice: voice)
                    .contextMenu { rowMenu(voice) }
            }
            Divider()
            mergeFooter
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Possible duplicates", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.duplicateSuggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.yellow.opacity(0.09))
    }

    private func suggestionRow(_ suggestion: DuplicateSuggestion) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(suggestion.primary.displayName) and \(suggestion.secondary.displayName)")
                    .font(.callout)
                Text("Sound alike. Merge into \(suggestion.primary.displayName)?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Merge") { Task { await model.mergeSuggestion(suggestion) } }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func rowMenu(_ voice: VoiceSummary) -> some View {
        Button("Rename…") {
            renameDraft = voice.name ?? ""
            renamingID = voice.id
        }
        Button("Forget…", role: .destructive) { forgettingID = voice.id }
    }

    private var mergeFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Merge Selected") { confirmingMerge = true }
                .disabled(!model.canMergeVoices)
            Text("Two entries for the same person? Select both and merge.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }
}

private struct VoiceRow: View {
    let voice: VoiceSummary

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color.speaker(for: voice.id))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(voice.displayName)
                    .foregroundStyle(voice.isNamed ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        "\(String(count: voice.sampleCount, "sample")) · in \(String(count: voice.recordingCount, "recording"))"
    }
}
