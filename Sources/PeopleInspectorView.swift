import SwiftUI

/// The People roster for the current transcript: who spoke, with turn and sample counts. Selecting
/// two speakers enables Merge, which fixes a voice the diarizer split into two.
struct PeopleInspectorView: View {
    @Bindable var model: LabelingModel

    var body: some View {
        VStack(spacing: 0) {
            List(model.rosterTokens, id: \.self, selection: $model.peopleSelection) { token in
                PersonRow(token: token, model: model)
                    .selectionDisabled(token == "you")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Button("Merge Selected") {
                    Task { await model.mergeSelected() }
                }
                .disabled(!model.canMerge)
                Text("Same person split into two voices? Select both and merge.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .navigationTitle("People")
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
        return "\(turnText) · \(samples) sample\(samples == 1 ? "" : "s")"
    }
}
