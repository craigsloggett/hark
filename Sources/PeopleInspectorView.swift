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
                    .selectionDisabled(token == "you")
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
        .alert("Rename Voice", isPresented: renamePresented, presenting: renamingID) { id in
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await model.renameVoice(id: id, to: renameDraft) } }
        } message: { _ in
            Text("Renames this saved voice everywhere it is used.")
        }
        .confirmationDialog(
            "Forget this voice?",
            isPresented: forgetPresented,
            titleVisibility: .visible,
            presenting: forgettingID
        ) { id in
            Button("Forget Voice", role: .destructive) { Task { await model.forgetVoice(id: id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Hark stops recognizing this voice. Turns labeled with it become unlabeled. You can undo this.")
        }
        .confirmationDialog("Merge these two voices?", isPresented: $confirmingMerge, titleVisibility: .visible) {
            Button("Merge", role: .destructive) {
                Task { await model.mergeSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They become one saved voice, keeping the named one. You can undo this.")
        }
    }

    @ViewBuilder
    private func rowMenu(_ token: String) -> some View {
        if case let .savedVoice(id) = model.binding(token: token) {
            Button("Rename Saved Voice…") {
                renameDraft = model.displayName(token: token) ?? ""
                renamingID = id
            }
            Button("Forget This Voice…", role: .destructive) {
                forgettingID = id
            }
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })
    }

    private var forgetPresented: Binding<Bool> {
        Binding(get: { forgettingID != nil }, set: { if !$0 { forgettingID = nil } })
    }
}

private struct PersonRow: View {
    let token: String
    let model: LabelingModel

    var body: some View {
        let name = model.displayName(token: token)
        let isYou = token == "you"
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
        let turns = model.turnCount(token: token)
        let turnText = "\(turns) turn\(turns == 1 ? "" : "s")"
        guard !isYou else { return turnText }
        let samples = model.sampleCount(token: token)
        var parts = [turnText, "\(samples) sample\(samples == 1 ? "" : "s")"]
        let others = model.otherRecordings(token: token)
        if others > 0 {
            parts.append("in \(others) other\(others == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
