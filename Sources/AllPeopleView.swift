import SwiftUI

/// The inspector's Everyone scope: all the people Hark knows across transcripts, with
/// cross-transcript rename, forget, and merge.
struct AllPeopleView: View {
    @Bindable var model: LabelingModel
    @State private var renamingID: String?
    @State private var renameDraft = ""
    @State private var forgettingID: String?
    @State private var confirmingMerge = false

    var body: some View {
        VStack(spacing: 0) {
            if model.voices.isEmpty {
                ContentUnavailableView(
                    "No people yet",
                    systemImage: "person.2.wave.2",
                    description: Text("Name a speaker in a transcript and they'll appear here.")
                )
            } else {
                List(model.voices, selection: $model.voicesSelection) { voice in
                    KnownPersonRow(voice: voice)
                        .contextMenu { rowMenu(voice) }
                }
                Divider()
            }
            footer
        }
        .renameVoiceAlert(id: $renamingID, draft: $renameDraft) { id, name in
            await model.renameVoice(id: id, to: name)
        }
        .forgetVoiceDialog(id: $forgettingID) { await model.forgetVoice(id: $0) }
        .mergeVoicesDialog(isPresented: $confirmingMerge) { await model.mergeSelectedVoices() }
    }

    @ViewBuilder
    private func rowMenu(_ voice: VoiceSummary) -> some View {
        Button {
            renameDraft = voice.name ?? ""
            renamingID = voice.id
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        Button(role: .destructive) {
            forgettingID = voice.id
        } label: {
            Label("Forget…", systemImage: "trash")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.voices.isEmpty {
                Button("Merge Selected") { confirmingMerge = true }
                    .disabled(!model.canMergeVoices)
                Text("Same person listed twice? Select both and merge.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Voices are recognized on this Mac and never leave it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }
}

private struct KnownPersonRow: View {
    let voice: VoiceSummary

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color.speaker(for: voice.id))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(voice.displayName)
                    .foregroundStyle(voice.isNamed ? .primary : .secondary)
                Text("In \(String(count: voice.recordingCount, "transcript"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
