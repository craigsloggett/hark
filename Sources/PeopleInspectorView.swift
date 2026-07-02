import SwiftUI

/// The People roster for the current transcript: who spoke, with turn and sample counts. A saved voice
/// can be renamed globally or forgotten from its row's context menu. Selecting two speakers enables
/// Merge, which fixes a voice the diarizer split into two.
struct PeopleInspectorView: View {
    @Bindable var model: LabelingModel
    @State private var renamingID: String?
    @State private var renameDraft = ""
    @State private var forgettingID: String?
    @State private var confirmingMerge = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("People")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            List(model.rosterTokens, id: \.self, selection: $model.peopleSelection) { token in
                PersonRow(token: token, model: model)
                    .selectionDisabled(token == Speaker.you.token)
                    .contextMenu { rowMenu(token) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Button("Merge Selected") {
                    confirmingMerge = true
                }
                .disabled(!model.canMerge)
                Text("Same person split into two voices? Select both and merge.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .renameVoiceAlert(id: $renamingID, draft: $renameDraft) { id, name in
            await model.renameVoice(id: id, to: name)
        }
        .forgetVoiceDialog(id: $forgettingID) { await model.forgetVoice(id: $0) }
        .mergeVoicesDialog(isPresented: $confirmingMerge) { await model.mergeSelected() }
    }

    @ViewBuilder
    private func rowMenu(_ token: String) -> some View {
        if case let .savedVoice(id) = model.resolver.binding(for: token) {
            Button("Rename Saved Voice…") {
                renameDraft = model.resolver.name(for: token) ?? ""
                renamingID = id
            }
            Button("Forget This Voice…", role: .destructive) {
                forgettingID = id
            }
        }
    }
}

private struct PersonRow: View {
    let token: String
    let model: LabelingModel

    var body: some View {
        let name = model.resolver.name(for: token)
        let isYou = token == Speaker.you.token
        HStack(spacing: 9) {
            Circle()
                .fill(isYou ? Color.accentColor : model.color(for: token))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? model.positionalLabel(token: token))
                    .foregroundStyle(name == nil && !isYou ? .secondary : .primary)
                Text(subtitle(isYou: isYou))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(isYou: Bool) -> String {
        let turnText = String(count: model.turnCount(token: token), "turn")
        guard !isYou else { return turnText }
        var parts = [turnText, String(count: model.sampleCount(token: token), "sample")]
        let others = model.otherRecordings(token: token)
        if others > 0 {
            parts.append("in \(String(count: others, "other"))")
        }
        return parts.joined(separator: " · ")
    }
}
