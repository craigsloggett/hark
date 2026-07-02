import SwiftUI

/// The sidebar: the global voices manager, then past recordings newest first, titled by their custom
/// name when one is set, otherwise by when they were recorded.
struct SessionListView: View {
    @Bindable var model: LabelingModel
    @State private var renamingURL: URL?

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                Label("All Voices", systemImage: "person.2.wave.2")
                    .tag(SidebarItem.voices)
            }
            Section("Recordings") {
                ForEach(model.library.sessions) { session in
                    SessionRow(session: session, model: model, renamingURL: $renamingURL)
                        .tag(SidebarItem.session(session.url))
                }
                if model.library.sessions.isEmpty {
                    Text("No recordings yet")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Hark")
    }
}

/// One recording row: the title with date and tag captions, swapping to an inline rename field on
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
                    caption(session.dateLabel)
                }
            }
            if !session.tags.isEmpty {
                caption(session.tags.joined(separator: " · "))
            }
        }
        .contextMenu {
            Button("Rename") { beginRenaming() }
        }
        .onTapGesture(count: 2) { beginRenaming() }
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
                isEditing = true
            }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
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
