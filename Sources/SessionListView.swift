import SwiftUI

/// The sidebar: past transcripts newest first, titled by their custom name when one is set,
/// otherwise by when they were recorded.
struct SessionListView: View {
    @Bindable var model: LabelingModel
    @State private var renamingURL: URL?

    var body: some View {
        List(selection: $model.selection) {
            Section("Transcripts") {
                ForEach(model.library.sessions) { session in
                    SessionRow(session: session, model: model, renamingURL: $renamingURL)
                        .tag(session.url)
                }
                if model.library.sessions.isEmpty {
                    emptyHint
                }
            }
        }
        .navigationTitle("Hark")
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No transcripts yet")
                .foregroundStyle(.secondary)
            Text("Record a meeting and it's transcribed right here on your Mac. Nothing leaves your device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One transcript row: the title with date and tag captions, swapping to an inline rename field on
/// demand (Freeform-style: Enter or clicking away commits, Esc cancels, empty clears the name).
private struct SessionRow: View {
    let session: SessionSummary
    let model: LabelingModel
    @Binding var renamingURL: URL?
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    private var isRenaming: Bool {
        renamingURL == session.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isRenaming {
                renameField
            } else {
                Text(session.title)
                if session.name != nil {
                    Text(session.dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !session.tags.isEmpty {
                TagChips(tags: session.tags)
            }
        }
        .contextMenu {
            Button("Rename") { beginRenaming() }
        }
        // An exclusive double-tap gesture holds the first click hostage while it waits for a second,
        // so clicking the label never reaches row selection; simultaneous recognition lets the click
        // select immediately while a real double-click still starts the rename.
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRenaming() })
    }

    private var renameField: some View {
        TextField(session.dateLabel, text: $draft)
            .focused($isEditing)
            .onSubmit { commit() }
            .onExitCommand { renamingURL = nil } // Esc cancels without committing.
            .onChange(of: isEditing) { _, focused in
                // Clicking away commits; `commit()` and Esc clear `renamingURL` first so the focus
                // change they themselves trigger doesn't commit a second time.
                if !focused, isRenaming { commit() }
            }
            .onAppear {
                draft = session.name ?? ""
                // Focusing during the insertion layout pass trips AppKit's layout-recursion check;
                // defer one turn so the field takes focus after layout settles.
                Task { isEditing = true }
            }
    }

    private func beginRenaming() {
        renamingURL = session.url
    }

    private func commit() {
        let name = draft
        renamingURL = nil
        Task { await model.renameSession(session.url, to: name) }
    }
}

/// A transcript's tags as caption-sized tinted capsules, capped so a long tag list can't crowd the
/// narrow sidebar row.
private struct TagChips: View {
    let tags: [String]

    private static let visibleLimit = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(Self.visibleLimit), id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(Color.tag(for: tag))
                    .background(Color.tag(for: tag).opacity(0.16), in: Capsule())
            }
            if tags.count > Self.visibleLimit {
                Text("+\(tags.count - Self.visibleLimit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
