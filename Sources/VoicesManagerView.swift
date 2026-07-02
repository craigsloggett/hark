import SwiftUI

/// Everyone Hark knows across all recordings, with cross-session rename, forget, and merge. Reached
/// from the recordings sidebar; its edits share the window's undo.
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
                    "No people yet",
                    systemImage: "person.2.wave.2",
                    description: Text("Name a speaker in a transcript and they'll appear here.")
                )
            } else {
                content
            }
        }
        .navigationTitle("People")
        .navigationSubtitle(subtitle)
        .renameVoiceAlert(id: $renamingID, draft: $renameDraft) { id, name in
            await model.renameVoice(id: id, to: name)
        }
        .forgetVoiceDialog(id: $forgettingID) { await model.forgetVoice(id: $0) }
        .mergeVoicesDialog(isPresented: $confirmingMerge) { await model.mergeSelectedVoices() }
    }

    private var subtitle: String {
        // "person" pluralizes irregularly, so the naive `String(count:)` helper doesn't apply.
        model.voices.count == 1 ? "1 person" : "\(model.voices.count) people"
    }

    private var content: some View {
        VStack(spacing: 0) {
            List(model.voices, selection: $model.voicesSelection) { voice in
                VoiceRow(voice: voice)
                    .contextMenu { rowMenu(voice) }
            }
            Divider()
            mergeFooter
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
            Text("Same person listed twice? Select both and merge.")
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
        "In \(String(count: voice.recordingCount, "recording"))"
    }
}
