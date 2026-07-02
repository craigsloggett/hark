import SwiftUI

/// The transcript toolbar's tag editor: add tags with the field, remove them per row. Tags label the
/// transcript in the sidebar; they never touch its text.
struct SessionTagsPopover: View {
    let model: LabelingModel
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TextField("Add a tag", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }
            tagList
        }
        .padding(14)
        .frame(width: 272)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tags")
                .font(.headline)
            Text(model.currentTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tagList: some View {
        let tags = model.currentSummary?.tags ?? []
        if tags.isEmpty {
            Text("No tags yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(tags, id: \.self) { tag in
                    tagRow(tag)
                }
            }
        }
    }

    private func tagRow(_ tag: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.tag(for: tag))
                .frame(width: 8, height: 8)
            Text(tag)
            Spacer()
            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove tag")
        }
    }

    private func add() {
        guard let url = model.selection else { return }
        let tag = draft
        draft = "" // The popover stays open so several tags can be added in a row.
        Task { await model.addSessionTag(tag, to: url) }
    }

    private func remove(_ tag: String) {
        guard let url = model.selection else { return }
        Task { await model.removeSessionTag(tag, from: url) }
    }
}
