import SwiftUI

/// The People inspector, in two scopes: who is in this transcript (with stats and merge), and
/// everyone Hark knows across transcripts. Renaming and forgetting live in the rows' context menus.
struct PeopleInspectorView: View {
    private enum Scope {
        case transcript
        case everyone
    }

    @Bindable var model: LabelingModel
    @State private var scope: Scope = .transcript
    @State private var renamingID: String?
    @State private var renameDraft = ""
    @State private var forgettingID: String?
    @State private var confirmingMerge = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if scope == .transcript {
                transcriptPeople
            } else {
                AllPeopleView(model: model)
            }
        }
        .renameVoiceAlert(id: $renamingID, draft: $renameDraft) { id, name in
            await model.renameVoice(id: id, to: name)
        }
        .forgetVoiceDialog(id: $forgettingID) { await model.forgetVoice(id: $0) }
        .mergeVoicesDialog(isPresented: $confirmingMerge) { await model.mergeSelected() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People")
                .font(.headline)
            Picker("Scope", selection: $scope) {
                Text("This Transcript").tag(Scope.transcript)
                Text("Everyone").tag(Scope.everyone)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var transcriptPeople: some View {
        if model.detail == nil {
            Spacer()
            Text("Select a transcript")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        } else {
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
                Text("Same person shown twice? Select both and merge.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ViewBuilder
    private func rowMenu(_ token: String) -> some View {
        if case let .savedVoice(id) = model.resolver.binding(for: token) {
            Button {
                renameDraft = model.resolver.name(for: token) ?? ""
                renamingID = id
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                forgettingID = id
            } label: {
                Label("Forget…", systemImage: "trash")
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
        var parts = [String(count: model.turnCount(token: token), "turn")]
        if let time = model.speakingTime(token: token) {
            parts.append(time)
        }
        let others = isYou ? 0 : model.otherRecordings(token: token)
        if others > 0 {
            parts.append("in \(String(count: others, "other transcript"))")
        }
        return parts.joined(separator: " · ")
    }
}
